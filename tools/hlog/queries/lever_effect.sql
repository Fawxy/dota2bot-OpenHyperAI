-- The lane controller's lever sizes measured (master slices/lane-controller.md, Open items "Order now" step 2), in games whose
-- file matches :like: one row per bucket of team-lane waves. A wave is the controller's decision (ev=lane_ctl kind=wave) with its
-- check 45 s on (kind=chk); `effect` = own45 - m45, what the lane did against the plain forecast in the team's frame (positive is
-- towards their tower). The bucket is what the laners did in that lane between the read and the check: `ours` the idle swing
-- kinds (predeny, setup, shove) of the team's own laners with an ok swing, `theirs` the other team's, `-` none. A hero's lane
-- is its position's (pos 1 and 5 the safe lane, 2 mid, 3 and 4 the offlane; Radiant's safe lane is bot, 3), so a hero out of
-- its lane is still counted there. `n` waves, `mean`/`sd` of effect, `swings` mean ok swings of ours per wave. The control is
-- the `-`/`-` bucket of the same games (the forecast's own error with no idle swing); a lever's size is its bucket's mean less
-- the control's. Hero hits other than idle swings (last hits, denies, harass) are not split out.
-- ensure: ev_lane_ctl(team, lane, kind, wave, own, m45)
-- ensure: ev_idle_swing(pid, kind, result)
-- ensure: ev_bot(pid, team, pos)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
hb AS MATERIALIZED (
    SELECT game_id, pid, max(team) AS team,
        (SELECT b2.pos FROM ev_bot b2 WHERE b2.game_id = b.game_id AND b2.pid = b.pid AND b2.pos IS NOT NULL ORDER BY b2.t DESC LIMIT 1) AS pos
    FROM ev_bot b WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2
),
hl AS MATERIALIZED (
    SELECT game_id, pid, team,
        CASE WHEN pos IN (1, 5) THEN (CASE WHEN team = 2 THEN 3 ELSE 1 END)
             WHEN pos = 2 THEN 2
             WHEN pos IN (3, 4) THEN (CASE WHEN team = 2 THEN 1 ELSE 3 END) END AS lane
    FROM hb
),
sw AS MATERIALIZED (
    SELECT i.game_id, i.t, i.kind, hl.team, hl.lane
    FROM ev_idle_swing i JOIN hl ON hl.game_id = i.game_id AND hl.pid = i.pid
    WHERE i.game_id IN (SELECT game_id FROM gm) AND i.result = 'ok'
),
w AS MATERIALIZED (
    SELECT d.game_id, d.team, d.lane, d.wave, d.m45, k.own - d.m45 AS effect
    FROM ev_lane_ctl d JOIN ev_lane_ctl k
        ON k.game_id = d.game_id AND k.team = d.team AND k.lane = d.lane AND k.kind = 'chk' AND k.wave = d.wave
    WHERE d.game_id IN (SELECT game_id FROM gm) AND d.kind = 'wave' AND d.m45 IS NOT NULL AND k.own IS NOT NULL
),
wk AS (
    SELECT w.*,
        coalesce((SELECT group_concat(DISTINCT s.kind) FROM (SELECT kind FROM sw WHERE sw.game_id = w.game_id AND sw.team = w.team AND sw.lane = w.lane AND sw.t >= w.wave + 2 AND sw.t < w.wave + 47 ORDER BY kind) s), '-') AS ours,
        coalesce((SELECT group_concat(DISTINCT s.kind) FROM (SELECT kind FROM sw WHERE sw.game_id = w.game_id AND sw.team <> w.team AND sw.lane = w.lane AND sw.t >= w.wave + 2 AND sw.t < w.wave + 47 ORDER BY kind) s), '-') AS theirs,
        (SELECT count(*) FROM sw WHERE sw.game_id = w.game_id AND sw.team = w.team AND sw.lane = w.lane AND sw.t >= w.wave + 2 AND sw.t < w.wave + 47) AS nsw
    FROM w
)
SELECT ours, theirs, count(*) AS n, round(avg(effect)) AS mean,
    round(sqrt(max(0, avg(effect * effect) - avg(effect) * avg(effect)))) AS sd, round(avg(nsw), 1) AS swings
FROM wk
GROUP BY 1, 2
ORDER BY n DESC;
