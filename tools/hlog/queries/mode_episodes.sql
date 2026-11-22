-- One row per stay of a hero in one mode (plan step 4, docs/team/VALVE-MODES.md): when the mode started, from what state, how
-- long it lasted and what took the hero next. An episode runs from an ev=mode row with to=:mode to the next row of that hero
-- with from=:mode; `nxt` and `xt` (so `secs`) are null for an episode the game ended in, whose snaps are read to the log's end.
-- The episode's snaps are those at or after its entry and before its exit (about one a second). State is its first one:
-- `hp0`, `ed0` (nearest visible enemy hero within 1,200, not the attack target; null if none), `ah0` (enemy heroes whose
-- attack target is the hero: targeted, not hit), `hit0` (damaged by a hero in the last second), `ce0` (enemy lane creeps
-- within 500); all null for an episode with no snap of its own (most under 1 s). `hp1` is its last snap's HP. `sn` counts its
-- snaps, `tgt_hero` those whose attack target is a hero (`tid` h<pid>).
-- `kills` is the hero's kill counter from its last snap at or before the entry to its last snap 3 s after the exit, or
-- before the next entry into this mode if sooner, so a kill falls in one episode of a mode.
-- The mode tracker does not run while a hero is dead, so `secs` holds dead time: `died` is 1 when the hero died in the
-- episode and `dead_secs` its seconds dead, from the gap in its snaps (the death within about a second of the last one).
-- Aggregates over it (share of seconds, quartiles, exits) are the reader's: `hlog q` has no way to nest a named query.
-- Params: like (LIKE pattern on games.file), mode (default attack), from, until (entry time in seconds, default 0 and 720).
-- ensure: ev_snap(pid, hp, ed, ah, hit, ce, tid, kills, deaths)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, (SELECT max(s.t) FROM ev_snap s WHERE s.game_id = games.game_id) AS gend
    FROM games WHERE file LIKE coalesce(:like, '%')),
e AS MATERIALIZED (
    SELECT m.game_id, m.pid, m.seq, m.t AS et, m.d AS d0, m."from" AS prev,
        (SELECT x.t FROM ev_mode x WHERE x.game_id = m.game_id AND x.pid = m.pid AND x.seq > m.seq AND x."from" = m."to" ORDER BY x.seq LIMIT 1) AS xt,
        (SELECT x."to" FROM ev_mode x WHERE x.game_id = m.game_id AND x.pid = m.pid AND x.seq > m.seq AND x."from" = m."to" ORDER BY x.seq LIMIT 1) AS nxt,
        (SELECT x.t FROM ev_mode x WHERE x.game_id = m.game_id AND x.pid = m.pid AND x.seq > m.seq AND x."to" = m."to" ORDER BY x.seq LIMIT 1) AS again,
        gm.gend
    FROM gm CROSS JOIN ev_mode m ON m.game_id = gm.game_id
    WHERE m."to" = coalesce(:mode, 'attack') AND m.t >= coalesce(:from, 0) AND m.t <= coalesce(:until, 720)
),
w AS MATERIALIZED (
    SELECT e.*, coalesce(e.xt, e.gend + 1) AS en,
        (SELECT s.rowid FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et AND s.t < coalesce(e.xt, e.gend + 1) ORDER BY s.t LIMIT 1) AS r0,
        (SELECT s.rowid FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et AND s.t < coalesce(e.xt, e.gend + 1) ORDER BY s.t DESC LIMIT 1) AS r1,
        (SELECT s.kills FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= e.et ORDER BY s.t DESC LIMIT 1) AS k0,
        (SELECT s.kills FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= min(coalesce(e.xt, e.gend) + 3, coalesce(e.again, e.gend + 4)) ORDER BY s.t DESC LIMIT 1) AS k1
    FROM e
),
-- A death: two of a hero's snaps in a row whose death counter rose, or its last snap well before the game's; dead from about a
-- second after the last snap alive to the next (or to the log's end).
sp AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t, s.deaths, gm.gend, lead(s.t) OVER o AS nt, lead(s.deaths) OVER o AS nd
    FROM gm CROSS JOIN ev_snap s ON s.game_id = gm.game_id
    WINDOW o AS (PARTITION BY s.game_id, s.pid ORDER BY s.t)
),
dz AS MATERIALIZED (
    SELECT game_id, pid, min(t + 1, coalesce(nt, gend)) AS d1, coalesce(nt, gend) AS d2
    FROM sp WHERE nd > deaths OR (nt IS NULL AND t < gend - 3)
)
SELECT w.game_id, w.pid, round(w.et, 1) AS t, round(w.xt - w.et, 1) AS secs, w.prev, w.nxt, w.d0,
    s0.hp AS hp0, s1.hp AS hp1, s0.ed AS ed0, s0.ah AS ah0, s0.hit AS hit0, s0.ce AS ce0,
    (SELECT count(*) FROM ev_snap s WHERE s.game_id = w.game_id AND s.pid = w.pid AND s.t >= w.et AND s.t < w.en) AS sn,
    (SELECT count(*) FROM ev_snap s WHERE s.game_id = w.game_id AND s.pid = w.pid AND s.t >= w.et AND s.t < w.en AND s.tid LIKE 'h%') AS tgt_hero,
    max(0, coalesce(w.k1, 0) - coalesce(w.k0, 0)) AS kills,
    (SELECT count(*) FROM dz WHERE dz.game_id = w.game_id AND dz.pid = w.pid AND dz.d1 >= w.et AND dz.d1 < w.en) AS died,
    round(coalesce((SELECT sum(min(w.en, dz.d2) - max(w.et, dz.d1)) FROM dz
        WHERE dz.game_id = w.game_id AND dz.pid = w.pid AND dz.d1 < w.en AND dz.d2 > w.et), 0), 1) AS dead_secs
FROM w
LEFT JOIN ev_snap s0 ON s0.rowid = w.r0
LEFT JOIN ev_snap s1 ON s1.rowid = w.r1
ORDER BY w.game_id, w.pid, w.et
