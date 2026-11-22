-- One row per stay of a hero in one mode (plan step 4, docs/team/VALVE-MODES.md): when the mode started, from what state, how
-- long it lasted and what took the hero next. An episode runs from an ev=mode row with to=:mode to the next row of that hero
-- with from=:mode; `nxt` and `xt` are null for an episode the game ended in. State is the first snap at or after the entry
-- (snaps are about one a second: `hp0` is null for an episode that ended before one). `tgt_hero` counts the episode's snaps
-- whose attack target is a hero (`tid` h<pid>); `sn` counts its snaps. `ed0` the nearest enemy hero within 1,200 (null if none),
-- `ah0` the enemy heroes whose attack target is the hero, `ce0` enemy lane creeps within 500. Kills are the hero's counter
-- from the entry to 3 s after the exit. Deaths are left out: snaps stop while a hero is dead, so the counter lags.
-- Aggregates over it (share of seconds, quartiles, exits) are the reader's: `hlog q` has no way to nest a named query.
-- Params: like (LIKE pattern on games.file), mode (default attack), from, until (entry time in seconds, default 0 and 720).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
e AS (
    SELECT m.game_id, m.pid, m.seq, m.t AS et, m.d AS d0, m."from" AS prev,
        (SELECT x.t FROM ev_mode x WHERE x.game_id = m.game_id AND x.pid = m.pid AND x.seq > m.seq AND x."from" = m."to" ORDER BY x.seq LIMIT 1) AS xt,
        (SELECT x."to" FROM ev_mode x WHERE x.game_id = m.game_id AND x.pid = m.pid AND x.seq > m.seq AND x."from" = m."to" ORDER BY x.seq LIMIT 1) AS nxt
    FROM ev_mode m JOIN gm ON gm.game_id = m.game_id
    WHERE m."to" = coalesce(:mode, 'attack') AND m.t >= coalesce(:from, 0) AND m.t <= coalesce(:until, 720)
)
SELECT e.game_id, e.pid, round(e.et, 1) AS t, round(e.xt - e.et, 1) AS secs, e.prev, e.nxt, e.d0,
    (SELECT s.hp FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et ORDER BY s.t LIMIT 1) AS hp0,
    (SELECT s.hp FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et AND s.t < coalesce(e.xt, e.et + 30) ORDER BY s.t DESC LIMIT 1) AS hp1,
    (SELECT s.ed FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et ORDER BY s.t LIMIT 1) AS ed0,
    (SELECT s.ah FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et ORDER BY s.t LIMIT 1) AS ah0,
    (SELECT s.ce FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et ORDER BY s.t LIMIT 1) AS ce0,
    (SELECT count(*) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et AND s.t < coalesce(e.xt, e.et + 30)) AS sn,
    (SELECT count(*) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et AND s.t < coalesce(e.xt, e.et + 30) AND s.tid LIKE 'h%') AS tgt_hero,
    coalesce((SELECT max(s.kills) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t < coalesce(e.xt, e.et + 30) + 3 AND s.t >= e.et), 0)
      - coalesce((SELECT min(s.kills) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t >= e.et), 0) AS kills
FROM e
ORDER BY e.game_id, e.pid, e.et
