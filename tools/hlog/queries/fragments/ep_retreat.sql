-- Fragment (`-- include: ep_retreat`): the one definition of a retreat bout. Needs what ep_second needs.
-- CTE `ep_retreat(game_id, pid, t0, t1, secs, hpmin)`: a run of a hero's live seconds in mode retreat, whoever's code holds
-- the mode, retreat seconds up to 3 s apart joined (a break of up to 2 s inside it); a death ends it. secs counts the retreat seconds only.
-- It is what the hero did. An episode of our retreat's decision (ev=retreat, query retreat_episodes) is another thing.
-- Ends with a comma.
-- include: ep_second
epr_s AS (
    SELECT s.game_id, s.pid, s.sec, s.hp, s.life, CASE WHEN s.sec - lag(s.sec) OVER w <= 3 THEN 0 ELSE 1 END AS brk
    FROM ep_sec s WHERE s.live AND s.mode = 'retreat'
    WINDOW w AS (PARTITION BY s.game_id, s.pid, s.life ORDER BY s.sec)
),
ep_retreat AS MATERIALIZED (
    SELECT game_id, pid, min(sec) AS t0, max(sec) AS t1, count(*) AS secs, min(hp) AS hpmin
    FROM (SELECT e.*, sum(brk) OVER (PARTITION BY game_id, pid, life ORDER BY sec) AS k FROM epr_s e)
    GROUP BY game_id, pid, life, k
),
