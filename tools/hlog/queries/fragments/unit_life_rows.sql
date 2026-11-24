-- Fragment (`-- include: unit_life_rows`): the one definition of view unit_life's rows (its header has the columns and rules).
-- The including query defines first, each `AS NOT MATERIALIZED`, the death events to read, all columns, of the games it wants
-- (view unit_life: every game; query unit_life and the readers of one run: their own games, so the cost follows the games read):
-- `ul_wave` the rows of ev_wave_creep_death, `ul_own` of ev_own_creep_death, `ul_enemy` of ev_creep_death, `ul_neu` of
-- ev_neutral_death, and `ul_useen`, `ul_ugone` the rows of ev_unit_seen and ev_unit_gone (from team-bots after 836e2a2d; the
-- game-filtering of every one is the includer's). A game with an ev_unit_seen row is read from those two (below); any other game
-- from the four death events, as before. CTE `unit_life_rows(game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind,
-- by_pid, by_src, src, hid)`. Ends with a comma.
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
ul_new AS MATERIALIZED (SELECT DISTINCT game_id FROM ul_useen),
-- A game with unit_seen rows (telemetry.ts trackCreepDeaths, ev=unit_seen / ev=unit_gone): a row per own lane creep, from its
-- owner's two lines, and one per neutral, the two teams' sightings merged. A cid is its team's own, so a unit is (team, cid).
ul_s AS NOT MATERIALIZED (SELECT game_id, seq, t, team, cid, kind, type, lane, camp, x, y FROM ul_useen),
ul_g AS NOT MATERIALIZED (
    SELECT game_id, seq, t, team, cid, x, y, CAST("by" AS TEXT) AS who, coalesce(hid, 0) AS hid FROM ul_ugone
),
ul_c AS MATERIALIZED (
    SELECT game_id, seq, t, 5 - team AS owner, kind, x, y, CAST("by" AS TEXT) AS who, coalesce(tw, 0) AS tw, cid
    FROM ul_enemy WHERE team IN (2, 3)
),
ul_o AS MATERIALIZED (
    SELECT w.game_id, w.seq, w.t, w.team, w.kind, w.x, w.y, CAST(w."by" AS TEXT) AS who, w.cid, w.lane, w.born, NULL AS utype, NULL AS x0, NULL AS y0
    FROM ul_wave w WHERE w.game_id NOT IN (SELECT game_id FROM ul_new)
    UNION ALL
    SELECT o.game_id, o.seq, o.t, o.team, o.kind, o.x, o.y, CAST(o."by" AS TEXT), o.cid, NULL, NULL, NULL, NULL, NULL
    FROM ul_own o
    WHERE o.game_id NOT IN (SELECT game_id FROM ul_new)
        AND NOT EXISTS (SELECT 1 FROM ul_wave w WHERE w.game_id = o.game_id AND w.team = o.team AND w.cid = o.cid)
    UNION ALL
    -- a game with unit_seen: every own lane creep, from its first sighting (born = its t to 0.1 s, as wave_creep_death's born is; alive at the end: no t, x, y, who), its kind as the
    -- old events name it (a flag bearer is a melee creep there, so the enemy's creep_death pairs by it) and its own type beside
    SELECT s.game_id, coalesce(g.seq, s.seq), g.t, s.team,
        CASE WHEN s.type LIKE '%siege%' THEN 'siege' WHEN s.type LIKE '%ranged%' THEN 'ranged' ELSE 'melee' END,
        g.x, g.y, g.who, s.cid, s.lane, round(s.t, 1),
        CASE WHEN s.type LIKE '%flagbearer%' THEN 'flag' END, s.x, s.y
    FROM ul_s s LEFT JOIN ul_g g ON g.game_id = s.game_id AND g.team = s.team AND g.cid = s.cid
    WHERE s.kind = 'lane'
),
ul_pair AS MATERIALIZED (
    SELECT game_id, oseq, sseq FROM (
        SELECT game_id, oseq, sseq,
            row_number() OVER (PARTITION BY game_id, oseq ORDER BY d2, dt, sseq) AS ro,
            row_number() OVER (PARTITION BY game_id, sseq ORDER BY d2, dt, oseq) AS rs
        FROM (
            SELECT u.game_id, u.seq AS oseq, s.seq AS sseq, abs(s.t - u.t) AS dt,
                (s.x - u.x) * (s.x - u.x) + (s.y - u.y) * (s.y - u.y) AS d2
            FROM ul_o u JOIN ul_c s ON s.game_id = u.game_id AND s.owner = u.team AND s.kind = u.kind
                AND s.t BETWEEN u.t - 1 AND u.t + 1 AND (s.x - u.x) * (s.x - u.x) + (s.y - u.y) * (s.y - u.y) <= 62500
        )
    ) WHERE ro = 1 AND rs = 1
),
-- A creep that leaves the taker's sight at low health is logged as a death (ev=creep_revive may follow), so one cid can have
-- several lines: an unpaired sighting is a unit only as its cid's last line, and not when another line of that cid paired.
ul_cpair AS MATERIALIZED (
    SELECT DISTINCT s.game_id, s.owner, s.cid FROM ul_pair p JOIN ul_c s ON s.game_id = p.game_id AND s.seq = p.sseq WHERE s.cid IS NOT NULL
),
ul_clast AS MATERIALIZED (
    SELECT game_id, owner, cid, max(seq) AS lastseq FROM ul_c WHERE cid IS NOT NULL GROUP BY game_id, owner, cid
),
ul_lane AS MATERIALIZED (
    SELECT u.game_id, u.team || ':' || coalesce(u.cid, 'e' || u.seq) AS uid, u.team, coalesce(u.utype, u.kind) AS type, u.lane, u.born,
        u.t, u.x, u.y, u.who AS owho, s.who AS swho, s.tw, s.seq IS NOT NULL AS paired, u.x0, u.y0
    FROM ul_o u
    LEFT JOIN ul_pair p ON p.game_id = u.game_id AND p.oseq = u.seq
    LEFT JOIN ul_c s ON s.game_id = p.game_id AND s.seq = p.sseq
    UNION ALL
    SELECT s.game_id, s.owner || ':' || 'x' || coalesce(s.cid, 'e' || s.seq), s.owner, s.kind, NULL, NULL,
        s.t, s.x, s.y, NULL, s.who, s.tw, 0, NULL, NULL
    FROM ul_c s
    WHERE s.game_id NOT IN (SELECT game_id FROM ul_new)
        AND NOT EXISTS (SELECT 1 FROM ul_pair p WHERE p.game_id = s.game_id AND p.sseq = s.seq)
        AND (s.cid IS NULL OR (s.seq = (SELECT c.lastseq FROM ul_clast c WHERE c.game_id = s.game_id AND c.owner = s.owner AND c.cid = s.cid)
            AND NOT EXISTS (SELECT 1 FROM ul_cpair c WHERE c.game_id = s.game_id AND c.owner = s.owner AND c.cid = s.cid)))
),
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
pts AS (SELECT game_id AS kind, uid AS k, 0 AS seq, t, x, y FROM ul_lane WHERE lane IS NULL),
-- include: lane_label
ul_all AS (
    SELECT l.game_id, l.uid, 'lane' AS kind, l.team, l.type, coalesce(l.lane, b.lane) AS lane, CAST(l.born / 30 AS INTEGER) AS wave,
        NULL AS camp, l.born AS t0, l.x0, l.y0, l.t AS t1, l.x AS x1, l.y AS y1,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') THEN 'hero'
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' OR l.swho = 'deny' THEN 'deny'
             WHEN l.tw = 1 THEN 'tower' ELSE 'unknown' END AS by_kind,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') THEN l.swho
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' THEN l.owho END AS by_pid,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') OR l.swho = 'deny' OR l.tw = 1 THEN CASE WHEN l.paired THEN 'paired' ELSE 'taker' END
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' THEN 'own' END AS by_src,
        NULL AS hid
    FROM ul_lane l LEFT JOIN lab b ON b.kind = l.game_id AND b.k = l.uid AND l.lane IS NULL
    UNION ALL
    SELECT game_id, uid, 'neutral', 4, NULL, NULL, NULL, camp, NULL, NULL, NULL, t, x, y,
        CASE WHEN who IS NOT NULL THEN 'hero' ELSE 'unknown' END, who,
        CASE WHEN who IS NULL THEN NULL WHEN from_b THEN 'paired' ELSE 'taker' END, NULL
    FROM ul_neutral
),
ul_all2 AS (
    SELECT n.game_id, n.uid, 'neutral' AS kind, 4 AS team, n.type, NULL AS lane, NULL AS wave, n.camp, n.t0, n.x0, n.y0, n.t1, n.x1, n.y1,
        CASE WHEN n.who IS NOT NULL THEN 'hero' ELSE 'unknown' END AS by_kind, n.who AS by_pid,
        CASE WHEN n.who IS NULL THEN NULL WHEN n.from_b THEN 'paired' ELSE 'taker' END AS by_src, n.hid
    FROM ul_nneutral n
),
unit_life_rows AS (
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, CAST(by_pid AS INTEGER) AS by_pid, by_src, 'log' AS src, hid FROM ul_all
    UNION ALL
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, CASE WHEN by_pid = 'none' THEN NULL ELSE CAST(by_pid AS INTEGER) END, by_src, 'log', hid FROM ul_all2
),
