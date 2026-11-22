-- Fragment (`-- include: ep_visit`): the one definition of a lane visit. Needs what ep_second needs; takes the CTE name `pts`.
-- CTEs:
--   ep_place(game_id, pid, sec, lane)      where each live second was: top, mid, bot, base or other (fragment lane_label)
--   ep_visit(game_id, pid, lane, t0, t1)   a stretch of 5 s or more in one lane, any lane and not only the hero's own, with
--                                          steps out of it of up to 5 s inside; a death ends it
-- Ends with a comma.
-- include: ep_second
pts AS (SELECT game_id AS kind, pid AS k, seq, sec AS t, x, y FROM ep_sec WHERE live),
-- include: lane_label
ep_place AS MATERIALIZED (SELECT kind AS game_id, k AS pid, t AS sec, lane FROM lab),
epv_s AS (
    SELECT p.game_id, p.pid, p.lane, p.sec, s.life, CASE WHEN p.sec - lag(p.sec) OVER w <= 6 THEN 0 ELSE 1 END AS brk
    FROM ep_place p JOIN ep_sec s ON s.game_id = p.game_id AND s.pid = p.pid AND s.sec = p.sec
    WHERE p.lane IN ('top', 'mid', 'bot')
    WINDOW w AS (PARTITION BY p.game_id, p.pid, p.lane, s.life ORDER BY p.sec)
),
ep_visit AS MATERIALIZED (
    SELECT game_id, pid, lane, min(sec) AS t0, max(sec) AS t1
    FROM (SELECT e.*, sum(brk) OVER (PARTITION BY game_id, pid, lane, life ORDER BY sec) AS k FROM epv_s e)
    GROUP BY game_id, pid, lane, life, k HAVING max(sec) - min(sec) >= 5
),
