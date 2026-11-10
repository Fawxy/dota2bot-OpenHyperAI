-- Retreat time per game and side (slice retreat-gone, master docs/team/slices/2026-11-10-retreat-gone.md): seconds in mode
-- retreat (fragment lane_rules' seconds: alive, HP above 0) split by whether an enemy hero was in reach (lr_f en_r: its
-- attack range + 600), and the no-reach seconds by which of our episodes held them (ev=retreat kind=ours, start to end):
--   secs, reach, noreach     every retreat second; with an enemy in reach; with none
--   nr_heal, nr_ep           no-reach seconds inside our heal episode; inside any other of our episodes (the run-on)
--   nr_high                  no-reach seconds at 80% HP or more
-- Params: like (file pattern), until (default 600: the 10:00 the scoreboard reads farm at).
-- ensure: ev_retreat(ph, pid, kind, ep, why)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
rt_st AS (
    SELECT r.game_id, r.pid, r.ep, r.t, r.why FROM ev_retreat r JOIN gm USING (game_id) WHERE r.ph = 'start' AND r.kind = 'ours'
),
rt_ep AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t AS t0, s.why,
        coalesce((SELECT min(e.t) FROM ev_retreat e WHERE e.game_id = s.game_id AND e.pid = s.pid AND e.ep = s.ep AND e.ph = 'end' AND e.kind = 'ours'), s.t + 40) AS t1
    FROM rt_st s
),
rt_s AS (
    SELECT f.game_id, f.side, f.en_r > 0 AS reach, f.hp >= 80 AS high,
        (SELECT ep.why FROM rt_ep ep WHERE ep.game_id = f.game_id AND ep.pid = f.pid AND f.sec >= ep.t0 AND f.sec <= ep.t1 LIMIT 1) AS why
    FROM lr_f f WHERE f.mode = 'retreat' AND f.sec <= coalesce(:until, 600)
)
SELECT gm.file, rt_s.side, count(*) AS secs, sum(reach) AS reach, sum(NOT reach) AS noreach,
    sum(NOT reach AND why = 'heal') AS nr_heal, sum(NOT reach AND why IS NOT NULL AND why <> 'heal') AS nr_ep,
    sum(NOT reach AND high) AS nr_high
FROM rt_s JOIN gm USING (game_id)
GROUP BY gm.file, rt_s.side
ORDER BY gm.file, rt_s.side
