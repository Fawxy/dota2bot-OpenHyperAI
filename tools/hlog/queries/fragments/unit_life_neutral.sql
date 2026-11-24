-- Fragment (`-- include: unit_life_neutral`): the neutrals' half of fragment unit_life_rows (read for its header: the rules), alone, for a reader that wants no lane creep and no replay
-- row. Needs `ul_neu` (fragment unit_life_in) and the fragment unit_life_seen's CTEs (`ul_new`, `ul_s`, `ul_g`) before it: a neutral-only reader includes unit_life_in, unit_life_seen, then this one;
-- unit_life_rows includes it after unit_life_lane, which has included unit_life_seen. CTEs `ul_n` .. `ul_nneutral` (the merging) and
-- `ul_nlife(game_id, uid, type, camp, t0, x0, y0, t1, x1, y1, by_kind, by_pid, by_src, hid, near_r, near_d)`: a row per neutral unit, the log's (never the replay's), as view unit_life's
-- neutral rows: `by_pid` an INTEGER or NULL; t1 NULL while a neutral was not found dead (a game with unit_seen: count dead neutrals by t1 set). `near_r`, `near_d`: 1 when Radiant's (Dire's) module saw the neutral die (it has a row of its own for the unit: an ev=neutral_death line, or a unit_seen / unit_gone pair) and a living Radiant
-- (Dire) hero stood within 1,500 of the spot in the second before t1, else 0 (NULL while t1 is). It is the gate ev=neutral_death had (a death its module saw within 1,500 of one of its heroes,
-- a row per such team), so a reader that took a team's own neutral deaths takes `near_r` (team 2) or `near_d` (team 3) = 1; the taker's team is its pid's, never the row's.
-- Ends with a comma.
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_snap(pid, alive, x, y)
-- ensure: ev_bot(pid, team)
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
        a.who = 'none' AND b.who IS NOT NULL AND b.who <> 'none' AS from_b,
        a.team = 2 AS seen_r, a.team = 3 OR b.seq IS NOT NULL AS seen_d
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
        (a.who IS NULL OR a.who = 'none') AND b.who IS NOT NULL AND b.who <> 'none' AS from_b,
        a.team = 2 AS seen_r, a.team = 3 OR b.cid IS NOT NULL AS seen_d
    FROM ul_nn a LEFT JOIN ul_nnpair p ON p.game_id = a.game_id AND p.acid = a.cid AND a.team = 2
    LEFT JOIN ul_nn b ON b.game_id = p.game_id AND b.team = 3 AND b.cid = p.bcid
    WHERE NOT (a.team = 3 AND EXISTS (SELECT 1 FROM ul_nnpair q WHERE q.game_id = a.game_id AND q.bcid = a.cid))
),
ul_nlife AS (
    SELECT n.game_id, n.uid, n.type, n.camp, n.t0, n.x0, n.y0, n.t1, n.x1, n.y1,
        CASE WHEN who IS NOT NULL THEN 'hero' ELSE 'unknown' END AS by_kind, CAST(who AS INTEGER) AS by_pid,
        CASE WHEN who IS NULL THEN NULL WHEN from_b THEN 'paired' ELSE 'taker' END AS by_src, hid,
        CASE WHEN n.t1 IS NOT NULL THEN n.seen_r AND EXISTS (
            SELECT 1 FROM ev_bot b JOIN ev_snap h ON h.game_id = b.game_id AND h.pid = b.pid AND h.t >= n.t1 - 1.0 AND h.t <= n.t1
            WHERE b.game_id = n.game_id AND b.team = 2 AND h.alive <> 0
                AND (h.x - n.x1) * (h.x - n.x1) + (h.y - n.y1) * (h.y - n.y1) <= 2250000) END AS near_r,
        CASE WHEN n.t1 IS NOT NULL THEN n.seen_d AND EXISTS (
            SELECT 1 FROM ev_bot b JOIN ev_snap h ON h.game_id = b.game_id AND h.pid = b.pid AND h.t >= n.t1 - 1.0 AND h.t <= n.t1
            WHERE b.game_id = n.game_id AND b.team = 3 AND h.alive <> 0
                AND (h.x - n.x1) * (h.x - n.x1) + (h.y - n.y1) * (h.y - n.y1) <= 2250000) END AS near_d
    FROM (
        SELECT game_id, uid, type, camp, t0, x0, y0, t1, x1, y1, who, from_b, hid, seen_r, seen_d FROM ul_nneutral
        UNION ALL
        SELECT game_id, uid, NULL, camp, NULL, NULL, NULL, t, x, y, who, from_b, NULL, seen_r, seen_d FROM ul_neutral
    ) n
),
