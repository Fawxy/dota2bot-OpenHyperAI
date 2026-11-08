-- The missing wave (slice lane-control 2c, ev=lane_ctl `ew`, bot humaniser/enemy_wave.ts) in games whose file matches
-- :like: one row per kind=wave read that took an `absent` resolution (`ew=a`: the enemy wave the tracker followed never
-- showed at its spot while our lead creep stood there), joined to the enemy team's ev=pull_job lines on that lane whose slot
-- falls in [t - 32, t) (the window their wave could have been pulled in; a read with several gives several rows, with none
-- one row with NULLs): `t` and `wave` the read's, `ewd` the wave's seconds from spawn to due, `ewp` (1 when Choose with the
-- pull on offer would have taken it, 0 when the model refused it anyway), `skip` (the line's rej has pull:ew), `lever` the
-- chosen set, `epid`/`epos` the enemy puller, `slot`, `res` and `div` its pull.
-- With :sum = 1 one summary row instead: n absent reads, `skipped`, `ewp1` (reads where the skip changed the set),
-- `pulled` (reads with an enemy `ok` pull in the window: the fact's precision is pulled / n), `enemy_ok` the enemy team's ok
-- pulls on the three lanes in the games, `caught` those with an `a` read on that lane in the 32 s after the slot (the
-- fact's recall is caught / enemy_ok).
-- ensure: ev_lane_ctl(team, lane, kind, wave, ew, ewp, ewd, rej, lever)
-- ensure: ev_pull_job(pid, pos, lane, slot, res, div)
-- ensure: ev_bot(pid, team)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE team IS NOT NULL GROUP BY 1, 2),
a AS MATERIALIZED (
    SELECT d.game_id, d.team, d.lane, d.t, d.wave, d.ewd, d.ewp, coalesce(d.lever, '') NOT LIKE '%pull%' AS skip, d.lever,
        CASE d.team WHEN 2 THEN 3 WHEN 3 THEN 2 END AS enemy
    FROM ev_lane_ctl d JOIN gm ON gm.game_id = d.game_id
    WHERE d.kind = 'wave' AND d.ew = 'a'
),
ep AS MATERIALIZED (
    SELECT p.game_id, tm.team, p.pid, p.pos, p.lane, p.slot, p.res, p.div
    FROM ev_pull_job p JOIN gm ON gm.game_id = p.game_id JOIN tm ON tm.game_id = p.game_id AND tm.pid = p.pid
),
rd AS (
    SELECT a.game_id, a.team, a.lane, a.t, a.wave, a.ewd, a.ewp, a.skip, a.lever, ep.pid AS epid, ep.pos AS epos, ep.slot, ep.res, ep.div
    FROM a LEFT JOIN ep ON ep.game_id = a.game_id AND ep.team = a.enemy AND ep.lane = a.lane AND ep.slot >= a.t - 32 AND ep.slot < a.t
)
SELECT 'read' AS row, game_id, team, lane, round(t, 1) AS t, wave, ewd, ewp, skip, lever, epid, epos, slot, res, div,
    NULL AS n, NULL AS skipped, NULL AS ewp1, NULL AS pulled, NULL AS enemy_ok, NULL AS caught
FROM rd WHERE coalesce(:sum, 0) = 0
UNION ALL
SELECT 'all', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    (SELECT count(*) FROM a),
    (SELECT sum(skip) FROM a),
    (SELECT sum(ewp = 1) FROM a),
    (SELECT count(*) FROM a WHERE EXISTS (SELECT 1 FROM ep WHERE ep.game_id = a.game_id AND ep.team = a.enemy AND ep.lane = a.lane
        AND ep.res = 'ok' AND ep.slot >= a.t - 32 AND ep.slot < a.t)),
    (SELECT count(*) FROM ep WHERE ep.res = 'ok' AND ep.lane IN (1, 2, 3)),
    (SELECT count(*) FROM ep WHERE ep.res = 'ok' AND ep.lane IN (1, 2, 3) AND EXISTS (SELECT 1 FROM a WHERE a.game_id = ep.game_id
        AND a.enemy = ep.team AND a.lane = ep.lane AND a.t > ep.slot AND a.t <= ep.slot + 32))
WHERE coalesce(:sum, 0) = 1
ORDER BY 1, 2, 5;
