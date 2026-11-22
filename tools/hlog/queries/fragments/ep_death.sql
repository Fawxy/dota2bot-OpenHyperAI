-- Fragment (`-- include: ep_death`): the one definition of a death. The including query defines `gm(game_id, ...)` first.
-- CTE `ep_death(game_id, pid, t, x, y, gap, n, open)` (x, y: where it was at t), one row per rise of a hero's deaths counter, any hero with snapshots:
--   t      its last living moment. Bots log nothing while dead, so the counter rises at the first snapshot after the respawn,
--          and the snapshots before that are not always the hero's life: a killed hero logs a few with HP 0 where it fell
--          (HP is a whole percent), and some also 1-5 at its fountain with HP rising from 0, then none for the respawn wait.
--          So the snapshot before the rise, moved back over a jump to the fountain (within 1,200 of it, over 1,200 in under
--          3 s) and to the last snapshot with HP above 0 (up to 15 s back).
--   gap    the snapshot before the rise: the hero is not playing in (t, gap]
--   n      the size of the rise
--   open   1 for a hero still dead when the log ends (its snapshots stop over 3 s before the game's last one): no rise seen
-- Deaths are dated over the whole game, whatever window the query reads. Ends with a comma.
-- ensure: ev_snap(pid, x, y, hp, deaths)
epd_raw AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.seq, s.t, s.deaths, s.x, s.y, s.hp
    FROM gm CROSS JOIN ev_snap s ON s.game_id = gm.game_id
    WHERE s.deaths IS NOT NULL
),
epd_last AS (SELECT game_id, max(t) AS t FROM epd_raw GROUP BY game_id),
-- A hero that never came back gets the rise its respawn would have logged.
epd_s0 AS (
    SELECT r.*, 0 AS open,
        ((r.x + 6700) * (r.x + 6700) + (r.y + 6700) * (r.y + 6700) <= 1200 * 1200
            OR (r.x - 6928) * (r.x - 6928) + (r.y - 6372) * (r.y - 6372) <= 1200 * 1200) AS nearf
    FROM epd_raw r
    UNION ALL
    SELECT h.game_id, h.pid, h.seq + 1, g.t, h.deaths + 1, NULL, NULL, NULL, 1, NULL
    FROM (SELECT game_id, pid, max(seq) AS seq, t, deaths FROM epd_raw GROUP BY game_id, pid) h
    JOIN epd_last g ON g.game_id = h.game_id
    WHERE g.t - h.t > 3
),
-- jump_from: the time of the last real snapshot when one lands at a fountain away from the one before it; last_ok: the last
-- snapshot with HP above 0.
epd_s1 AS (
    SELECT s.*, lag(s.deaths) OVER w AS prev, lag(s.t) OVER w AS prev_t, lag(s.nearf) OVER w AS prev_nearf,
        CASE WHEN s.nearf AND s.t - lag(s.t) OVER w < 3
            AND (s.x - lag(s.x) OVER w) * (s.x - lag(s.x) OVER w) + (s.y - lag(s.y) OVER w) * (s.y - lag(s.y) OVER w) > 1200 * 1200
            THEN lag(s.t) OVER w END AS jump_from
    FROM epd_s0 s
    WINDOW w AS (PARTITION BY s.game_id, s.pid ORDER BY s.seq)
),
epd_s2 AS (
    SELECT s.*, max(CASE WHEN s.hp > 0 THEN s.t END) OVER (PARTITION BY s.game_id, s.pid ORDER BY s.t) AS last_ok FROM epd_s1 s
),
-- jump_ok: the last snapshot with HP above 0 before the jump (the one before it can itself read HP 0).
epd_s3 AS (
    SELECT s.*, CASE WHEN s.jump_from IS NOT NULL THEN lag(s.last_ok) OVER w END AS jump_ok FROM epd_s2 s
    WINDOW w AS (PARTITION BY s.game_id, s.pid ORDER BY s.seq)
),
epd_s4 AS (
    SELECT s.*, min(s.jump_ok) OVER (PARTITION BY s.game_id, s.pid ORDER BY s.t RANGE BETWEEN 8 PRECEDING AND CURRENT ROW) AS jt
    FROM epd_s3 s
),
epd_s5 AS (
    SELECT s.*, lag(s.jt) OVER w AS prev_jt, lag(s.last_ok) OVER w AS prev_ok FROM epd_s4 s
    WINDOW w AS (PARTITION BY s.game_id, s.pid ORDER BY s.seq)
),
epd_d AS (
    SELECT game_id, pid, CASE WHEN prev_ok >= c - 15 THEN min(prev_ok, c) ELSE c END AS t, prev_t AS gap,
        CAST(ceil(deaths - prev) AS INTEGER) AS n, open
    FROM (SELECT s.*, CASE WHEN prev_nearf AND prev_jt IS NOT NULL THEN prev_jt ELSE prev_t END AS c FROM epd_s5 s)
    WHERE prev IS NOT NULL AND deaths > prev
),
ep_death AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.t,
        (SELECT s.x FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = d.pid AND s.t = d.t LIMIT 1) AS x,
        (SELECT s.y FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = d.pid AND s.t = d.t LIMIT 1) AS y,
        d.gap, d.n, d.open
    FROM epd_d d
),
