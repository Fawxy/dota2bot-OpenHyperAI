-- The lane controller's shadow decisions (slice lane-control 2a, ev=lane_ctl) in games whose file matches :like, scored
-- against the clash LaneControl Horizon (45) s later: each kind=wave line joined to the kind=chk line of the same game, team,
-- lane and wave. One row per group of `pulled` (1 when an `ok` ev=pull_job of that team and lane has its slot in the wave's
-- 30 s, so the pull acted on that wave; 0 otherwise), `intent` and `lever` (the chosen set), plus an `all` row per pulled group:
--   n decisions with a check; e_none |own - own45| (no change), e_plain |m45 - own45| (the plain forecast), e_ctl the
--   controller's prediction for what happened, m45 + pe on pulled waves and m45 otherwise; in_band the share whose own45 sat
--   within LaneControl Band (150) of the target; mean_n45 the predicted need; mean_left the chosen set's predicted remainder;
--   nearer (slice 2b's intent met) the share whose own45 sat nearer the target than the decision's own reading did, over
--   the waves whose intent asked for a change (back, forward, reset; NULL on hold rows).
-- `div` (slice 2b, review 2026-11-06-lane-control-3115b32 L3): 1 when a pulled wave's ok pull diverted half its creeps or more
-- (ev=pull_job div >= 0.5), 0 on undiverted pulls and unpulled waves; groups by pulled, div, intent, lever.
-- own45 is the team's own reading at the check (its view: visible enemy creeps and the spawn schedule), not the census.
-- ensure: ev_lane_ctl(team, lane, kind, wave, intent, lever, own, m45, pe, n45, tgt, left)
-- ensure: ev_pull_job(pid, lane, slot, res, div)
-- ensure: ev_bot(pid, team)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE team IS NOT NULL GROUP BY 1, 2),
w AS MATERIALIZED (
    SELECT d.game_id, d.team, d.lane, d.wave, d.intent, d.lever, d.own, d.m45, d.pe, d.n45, d.tgt, d.left, c.own AS own45,
        EXISTS (SELECT 1 FROM ev_pull_job p JOIN tm ON tm.game_id = p.game_id AND tm.pid = p.pid
            WHERE p.game_id = d.game_id AND tm.team = d.team AND p.lane = d.lane AND p.res = 'ok'
                AND p.slot >= d.wave AND p.slot < d.wave + 30) AS pulled,
        EXISTS (SELECT 1 FROM ev_pull_job p JOIN tm ON tm.game_id = p.game_id AND tm.pid = p.pid
            WHERE p.game_id = d.game_id AND tm.team = d.team AND p.lane = d.lane AND p.res = 'ok' AND p.div >= 0.5
                AND p.slot >= d.wave AND p.slot < d.wave + 30) AS div
    FROM ev_lane_ctl d
    JOIN gm ON gm.game_id = d.game_id
    JOIN ev_lane_ctl c ON c.game_id = d.game_id AND c.team = d.team AND c.lane = d.lane AND c.kind = 'chk' AND c.wave = d.wave
    WHERE d.kind = 'wave' AND d.m45 IS NOT NULL AND c.own IS NOT NULL
),
s AS (
    SELECT pulled, div, intent, lever, own, m45, own45, tgt, n45, left,
        CASE WHEN intent IN ('back', 'forward', 'reset') THEN abs(own45 - tgt) < abs(own - tgt) END AS nearer,
        CASE WHEN pulled = 1 AND pe IS NOT NULL THEN m45 + pe ELSE m45 END AS ctl
    FROM w
)
SELECT * FROM (
SELECT pulled, div, intent, lever, count(*) AS n,
    round(avg(abs(own - own45))) AS e_none,
    round(avg(abs(m45 - own45))) AS e_plain,
    round(avg(abs(ctl - own45))) AS e_ctl,
    round(avg(abs(own45 - tgt) <= 150), 2) AS in_band,
    round(avg(n45)) AS mean_n45,
    round(avg(left)) AS mean_left,
    round(avg(nearer), 2) AS nearer
FROM s GROUP BY pulled, div, intent, lever
UNION ALL
SELECT pulled, div, 'all', 'all', count(*), round(avg(abs(own - own45))), round(avg(abs(m45 - own45))), round(avg(abs(ctl - own45))),
    round(avg(abs(own45 - tgt) <= 150), 2), round(avg(n45)), round(avg(left)), round(avg(nearer), 2)
FROM s GROUP BY pulled, div
) ORDER BY pulled, div, intent = 'all', intent, n DESC;
