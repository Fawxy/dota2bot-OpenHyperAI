-- Fragment (`-- include: unit_life_rows`): the one definition of view unit_life's rows (its header has the columns and rules).
-- The including query defines first, each `AS NOT MATERIALIZED`, the death events to read, all columns, of the games it wants
-- (view unit_life: every game; query unit_life and the readers of one run: their own games, so the cost follows the games read):
-- `ul_wave` the rows of ev_wave_creep_death, `ul_own` of ev_own_creep_death, `ul_enemy` of ev_creep_death, `ul_neu` of
-- ev_neutral_death, and `ul_useen`, `ul_ugone` the rows of ev_unit_seen and ev_unit_gone (from team-bots after 836e2a2d; the
-- game-filtering of every one is the includer's). A game with an ev_unit_seen row is read from those two (below); any other game
-- from the four death events, as before. CTEs `unit_life_log` (the log's rows) and `unit_life_rows(game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind,
-- by_pid, by_src, src, hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near)`. Ends with a comma.
-- A creep_death line (the other team's sighting) is written when a creep at low health leaves the writer's unit list
-- (trackCreepDeaths, telemetry.ts), which can be a creep that went into fog and lived: ev=creep_revive is written if it reappears,
-- with no cid. So a row with by_src = taker whose uid has `:x` (no owner line) is a sighting, not a confirmed death; a paired
-- row is confirmed by the owner's own line.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
-- Also `ul_rp`: the rows of rp_unit (written by `hlog.js replay`, always there) of the games wanted, all columns, with t1 NULL unless end = death.
-- include: unit_life_lane
ul_n AS NOT MATERIALIZED (
    SELECT game_id, seq, t, team, x, y, CAST("by" AS TEXT) AS who, camp FROM ul_neu WHERE game_id NOT IN (SELECT game_id FROM ul_new)
),
ul_npair AS (
    SELECT game_id, aseq, bseq FROM (
        SELECT game_id, aseq, bseq,
            row_number() OVER (PARTITION BY game_id, aseq ORDER BY d2, dt, bseq) AS ra,
            row_number() OVER (PARTITION BY game_id, bseq ORDER BY d2, dt, aseq) AS rb
        FROM (
            SELECT a.game_id, a.seq AS aseq, b.seq AS bseq, abs(b.t - a.t) AS dt,
                (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) AS d2
            FROM ul_n a JOIN ul_n b ON b.game_id = a.game_id AND a.team = 2 AND b.team = 3
                AND b.t BETWEEN a.t - 1 AND a.t + 1 AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= 62500
            WHERE a.who = 'none' OR b.who = 'none'
        )
    ) WHERE ra = 1 AND rb = 1
),
ul_neutral AS (
    SELECT a.game_id, 'n' || a.team || ':' || a.seq AS uid, a.t, a.x, a.y, coalesce(a.camp, b.camp) AS camp,
        CASE WHEN a.who <> 'none' THEN a.who WHEN b.who <> 'none' THEN b.who END AS who,
        a.who = 'none' AND b.who IS NOT NULL AND b.who <> 'none' AS from_b
    FROM ul_n a LEFT JOIN ul_npair p ON p.game_id = a.game_id AND p.aseq = a.seq
    LEFT JOIN ul_n b ON b.game_id = p.game_id AND b.seq = p.bseq
    WHERE NOT (a.team = 3 AND EXISTS (SELECT 1 FROM ul_npair q WHERE q.game_id = a.game_id AND q.bseq = a.seq))
),
-- A neutral both teams saw die is one unit: the two gone rows of the same type within 1 s and 250 units, mutually nearest (the rule the old
-- neutral_death pairing has). A row with hid = 1 was found dead only after it left the list: its t1 is when that was noticed and its spot the
-- last one seen, so it pairs differently (below). A unit only one team logged, or a neutral still alive when the log stopped, is one row per team.
ul_nn AS MATERIALIZED (
    SELECT s.game_id, s.team, s.cid, s.type, s.camp, s.t AS t0, s.x AS x0, s.y AS y0, g.t AS t1, g.x AS x1, g.y AS y1, g.who, g.hid
    FROM ul_s s LEFT JOIN ul_g g ON g.game_id = s.game_id AND g.team = s.team AND g.cid = s.cid
    WHERE s.kind = 'neutral'
),
ul_nnexact AS MATERIALIZED (
    SELECT game_id, acid, bcid FROM (
        SELECT game_id, acid, bcid,
            row_number() OVER (PARTITION BY game_id, acid ORDER BY d2, dt, bcid) AS ra,
            row_number() OVER (PARTITION BY game_id, bcid ORDER BY d2, dt, acid) AS rb
        FROM (
            SELECT a.game_id, a.cid AS acid, b.cid AS bcid, abs(b.t1 - a.t1) AS dt,
                (b.x1 - a.x1) * (b.x1 - a.x1) + (b.y1 - a.y1) * (b.y1 - a.y1) AS d2
            FROM ul_nn a JOIN ul_nn b ON b.game_id = a.game_id AND a.team = 2 AND b.team = 3 AND a.type = b.type
                AND a.hid = 0 AND b.hid = 0 AND abs(b.t1 - a.t1) <= 1
                AND (b.x1 - a.x1) * (b.x1 - a.x1) + (b.y1 - a.y1) * (b.y1 - a.y1) <= 62500
        )
    ) WHERE ra = 1 AND rb = 1
),
-- A pair with a hid row: its spot is where the neutral was last listed, which may be far from where it died (pulled or moved), so no
-- distance gate: the same type and camp (a neutral outside any camp is never merged this way) and t1 within 2 s, mutually nearest
-- by time among the rows no exact pair took.
ul_nnhid AS MATERIALIZED (
    SELECT game_id, acid, bcid FROM (
        SELECT game_id, acid, bcid,
            row_number() OVER (PARTITION BY game_id, acid ORDER BY dt, d2, bcid) AS ra,
            row_number() OVER (PARTITION BY game_id, bcid ORDER BY dt, d2, acid) AS rb
        FROM (
            SELECT a.game_id, a.cid AS acid, b.cid AS bcid, abs(b.t1 - a.t1) AS dt,
                (b.x1 - a.x1) * (b.x1 - a.x1) + (b.y1 - a.y1) * (b.y1 - a.y1) AS d2
            FROM ul_nn a JOIN ul_nn b ON b.game_id = a.game_id AND a.team = 2 AND b.team = 3 AND a.type = b.type
                AND (a.hid = 1 OR b.hid = 1) AND a.camp IS NOT NULL AND a.camp = b.camp AND abs(b.t1 - a.t1) <= 2
            WHERE NOT EXISTS (SELECT 1 FROM ul_nnexact e WHERE e.game_id = a.game_id AND (e.acid = a.cid OR e.bcid = b.cid))
        )
    ) WHERE ra = 1 AND rb = 1
),
ul_nnpair AS (
    SELECT game_id, acid, bcid FROM ul_nnexact
    UNION ALL
    SELECT game_id, acid, bcid FROM ul_nnhid
),
ul_nneutral AS (
    SELECT a.game_id, 'n' || a.team || ':' || a.cid AS uid, a.type, coalesce(a.camp, b.camp) AS camp,
        CASE WHEN b.t0 IS NOT NULL AND b.t0 < a.t0 THEN b.t0 ELSE a.t0 END AS t0, a.x0, a.y0,
        CASE WHEN a.hid = 1 AND b.hid = 0 THEN b.t1 ELSE a.t1 END AS t1, CASE WHEN a.hid = 1 AND b.hid = 0 THEN b.x1 ELSE a.x1 END AS x1,
        CASE WHEN a.hid = 1 AND b.hid = 0 THEN b.y1 ELSE a.y1 END AS y1, CASE WHEN a.hid = 1 AND b.hid = 0 THEN 0 ELSE a.hid END AS hid,
        CASE WHEN a.who IS NOT NULL AND a.who <> 'none' THEN a.who WHEN b.who IS NOT NULL AND b.who <> 'none' THEN b.who END AS who,
        (a.who IS NULL OR a.who = 'none') AND b.who IS NOT NULL AND b.who <> 'none' AS from_b
    FROM ul_nn a LEFT JOIN ul_nnpair p ON p.game_id = a.game_id AND p.acid = a.cid AND a.team = 2
    LEFT JOIN ul_nn b ON b.game_id = p.game_id AND b.team = 3 AND b.cid = p.bcid
    WHERE NOT (a.team = 3 AND EXISTS (SELECT 1 FROM ul_nnpair q WHERE q.game_id = a.game_id AND q.bcid = a.cid))
),
-- A creep only the taker saw has no lane from an owner's line: its place is labelled (fragment lane_label, under other names).
ul_pts AS (SELECT game_id AS kind, uid AS k, 0 AS seq, t1 AS t, x1 AS x, y1 AS y FROM ul_lall WHERE lane IS NULL),
-- include: lane_label pts=ul_pts lab=ul_lab
ul_all AS (
    SELECT l.game_id, l.uid, l.kind, l.team, l.type, coalesce(l.lane, b.lane) AS lane, l.wave, l.camp, l.t0, l.x0, l.y0, l.t1, l.x1, l.y1, l.by_kind, l.by_pid, l.by_src, l.hid,
        l.cd_seq, l.cd_t, l.cd_x, l.cd_y, l.tw, l.seq, l.hp1, l.near
    FROM ul_lall l LEFT JOIN ul_lab b ON b.kind = l.game_id AND b.k = l.uid AND l.lane IS NULL
    UNION ALL
    SELECT game_id, uid, 'neutral', 4, NULL, NULL, NULL, camp, NULL, NULL, NULL, t, x, y,
        CASE WHEN who IS NOT NULL THEN 'hero' ELSE 'unknown' END, who,
        CASE WHEN who IS NULL THEN NULL WHEN from_b THEN 'paired' ELSE 'taker' END, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM ul_neutral
),
ul_all2 AS (
    SELECT n.game_id, n.uid, 'neutral' AS kind, 4 AS team, n.type, NULL AS lane, NULL AS wave, n.camp, n.t0, n.x0, n.y0, n.t1, n.x1, n.y1,
        CASE WHEN n.who IS NOT NULL THEN 'hero' ELSE 'unknown' END AS by_kind, n.who AS by_pid,
        CASE WHEN n.who IS NULL THEN NULL WHEN n.from_b THEN 'paired' ELSE 'taker' END AS by_src, n.hid,
        NULL AS cd_seq, NULL AS cd_t, NULL AS cd_x, NULL AS cd_y, NULL AS tw, NULL AS seq, NULL AS hp1, NULL AS near
    FROM ul_nneutral n
),
unit_life_log AS (
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, CAST(by_pid AS INTEGER) AS by_pid, by_src, 'log' AS src, hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near FROM ul_all
    UNION ALL
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, CASE WHEN by_pid = 'none' THEN NULL ELSE CAST(by_pid AS INTEGER) END, by_src, 'log', hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near FROM ul_all2
),
-- A game with replay rows (rp_game, written by `hlog.js replay`): its units are the replay's, whole (no log row of it is read, and none is paired
-- to one: a unit's uid is the replay's entity and use, `<ent>.<n>`). lane is where the creep was 20 s after it spawned, wave floor(t0 / 30), t1 x1 y1
-- the death (NULL for a unit alive at 12:00 or despawned: those have by_kind NULL), by_kind also creep or neutral, by_src replay (replay_amb: two
-- like units died within 0.1 s with different killers, so the killers may be swapped), src replay. Any other game reads exactly as `unit_life_log`.
-- Fragment wave_fate reads `unit_life_log`, so the pull readers give the same answers with or without a replay; query unit_grade reads both.
unit_life_rows AS (
    SELECT * FROM unit_life_log WHERE game_id NOT IN (SELECT game_id FROM rp_game)
    UNION ALL
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, by_pid,
        CASE WHEN by_kind IS NULL THEN NULL WHEN amb = 1 THEN 'replay_amb' ELSE 'replay' END, 'replay', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM ul_rp
),
