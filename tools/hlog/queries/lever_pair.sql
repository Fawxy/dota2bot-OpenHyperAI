-- A lever drill's input arm against its control arm, wave by wave (master slices/lane-controller.md "Drills", the lever
-- drills): the game whose file matches :on and the one matching :off (same drill seed, so the same waves), on :team's side of
-- :lane (defaults Radiant bot). One row per wave both games decided and checked: `on_eff`/`off_eff` own45 - m45 (the clash at
-- the check against the plain forecast, in the team's frame), `diff` on_eff - off_eff (the lever's effect on that wave),
-- `on_sw`/`off_sw` the team's ok idle swings in the 45 s (all kinds). With :sum = 1 one row: `n` waves, `mean` and `se` of
-- diff (se = sd / sqrt(n)), the per-wave swings of each arm. A wave's lever spills into the next (45 s horizon, 30 s waves),
-- so waves are not independent and `se` is optimistic.
-- ensure: ev_lane_ctl(team, lane, kind, wave, own, m45)
-- ensure: ev_idle_swing(pid, result)
-- ensure: ev_bot(pid, team)
WITH
g AS MATERIALIZED (
    SELECT (SELECT max(game_id) FROM games WHERE file LIKE :on) AS gon, (SELECT max(game_id) FROM games WHERE file LIKE :off) AS goff
),
e AS MATERIALIZED (
    SELECT d.game_id, d.wave, k.own - d.m45 AS eff,
        (SELECT count(*) FROM ev_idle_swing i
         WHERE i.game_id = d.game_id AND i.result = 'ok' AND i.t >= d.wave + 2 AND i.t < d.wave + 47
           AND EXISTS (SELECT 1 FROM ev_bot b WHERE b.game_id = i.game_id AND b.pid = i.pid AND b.team = d.team)) AS sw
    FROM ev_lane_ctl d JOIN ev_lane_ctl k
        ON k.game_id = d.game_id AND k.team = d.team AND k.lane = d.lane AND k.kind = 'chk' AND k.wave = d.wave
    WHERE d.game_id IN ((SELECT gon FROM g), (SELECT goff FROM g)) AND d.kind = 'wave'
        AND d.team = coalesce(:team, 2) AND d.lane = coalesce(:lane, 3) AND d.m45 IS NOT NULL AND k.own IS NOT NULL
),
p AS (
    SELECT a.wave, a.eff AS on_eff, b.eff AS off_eff, a.eff - b.eff AS diff, a.sw AS on_sw, b.sw AS off_sw
    FROM e a JOIN e b ON a.wave = b.wave
    WHERE a.game_id = (SELECT gon FROM g) AND b.game_id = (SELECT goff FROM g)
)
SELECT * FROM (
    SELECT wave, on_eff, off_eff, diff, on_sw, off_sw, NULL AS n, NULL AS mean, NULL AS se FROM p WHERE coalesce(:sum, 0) = 0
    UNION ALL
    SELECT NULL, NULL, NULL, NULL, round(avg(on_sw), 1), round(avg(off_sw), 1), count(*), round(avg(diff)),
        round(sqrt(max(0, avg(diff * diff) - avg(diff) * avg(diff)) / max(1, count(*) - 1)))
    FROM p WHERE coalesce(:sum, 0) = 1 HAVING count(*) > 0
)
ORDER BY wave;
