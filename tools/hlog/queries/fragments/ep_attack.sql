-- Fragment (`-- include: ep_attack`): hero attacks on heroes, which exchanges and kill attempts are cut from. Needs what
-- ep_second needs. CTEs:
--   ep_hit(game_id, apid, team, sec, tpid)   a second in which a hero's attack target (snapshot `tid`) is an enemy hero
--   ep_run(game_id, team, tpid, t0, t1)      one side's attacks on one target, a new run when attack seconds are more than 5 s apart
-- A spell names no target in the logs, so a cast alone is no attack. A log without `tid` has none (the timeline's not_logged row says so).
-- Ends with a comma.
-- include: ep_second
ep_hit AS MATERIALIZED (
    SELECT s.game_id, s.pid AS apid, s.team, s.sec, w.pid AS tpid
    FROM ep_sec s JOIN ep_who w ON w.game_id = s.game_id AND s.tid = 'h' || w.pid AND w.team <> s.team
    WHERE s.alive = 1
),
epa_s AS (
    SELECT h.*, CASE WHEN h.sec - lag(h.sec) OVER w <= 5 THEN 0 ELSE 1 END AS brk
    FROM (SELECT DISTINCT game_id, team, tpid, sec FROM ep_hit) h
    WINDOW w AS (PARTITION BY h.game_id, h.team, h.tpid ORDER BY h.sec)
),
ep_run AS MATERIALIZED (
    SELECT game_id, team, tpid, min(sec) AS t0, max(sec) AS t1
    FROM (SELECT e.*, sum(brk) OVER (PARTITION BY game_id, team, tpid ORDER BY sec) AS k FROM epa_s e)
    GROUP BY game_id, team, tpid, k
),
