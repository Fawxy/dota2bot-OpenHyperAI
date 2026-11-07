-- The offlane pull by the pos3 (slice lane-control 4a, Ours.CorePull) in games whose file matches :like. Rows by `row`:
--   `wave`: the offlane's (Radiant top, Dire bot) kind=wave decisions with intent `back`, grouped by `pby` (who the pull lever
--   went to: core, sup, none) and `okby` (the pos of the ok ev=pull_job of that team and lane whose slot falls in the wave's
--   30 s, none without one): n waves, chose (the lever set has the pull), no_puller (no pull and the lever refused `no_sup`,
--   `away` or `stack`), no_puller_in (the coverage count: those with a laner in lane and the rule not R6, so a puller could
--   have gone), nearer (intent met: the clash at the kind=chk line nearer the target than at the
--   read; NULL with no check).
--   `start`: the pos3's pull_job lines (every start ends in one): n starts, ok their `ok` share; `start_died`: n the deaths in
--   them.
-- ensure: ev_lane_ctl(team, lane, kind, wave, intent, lever, rej, own, tgt, pby, rule, core, sup)
-- ensure: ev_pull_job(pid, pos, lane, slot, res, died)
-- ensure: ev_bot(pid, team)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE team IS NOT NULL GROUP BY 1, 2),
w AS MATERIALIZED (
    SELECT d.game_id, d.team, d.lane, d.wave, d.lever, d.rej, d.own, d.tgt, d.rule, (d.core IS NOT NULL OR d.sup IS NOT NULL) AS anyin, coalesce(d.pby, 'none') AS pby,
        (SELECT c.own FROM ev_lane_ctl c WHERE c.game_id = d.game_id AND c.team = d.team AND c.lane = d.lane AND c.kind = 'chk'
            AND c.wave = d.wave LIMIT 1) AS own45,
        (SELECT max(p.pos) FROM ev_pull_job p JOIN tm ON tm.game_id = p.game_id AND tm.pid = p.pid
            WHERE p.game_id = d.game_id AND tm.team = d.team AND p.lane = d.lane AND p.res = 'ok'
                AND p.slot >= d.wave AND p.slot < d.wave + 30) AS okpos
    FROM ev_lane_ctl d JOIN gm ON gm.game_id = d.game_id
    WHERE d.kind = 'wave' AND d.intent = 'back' AND ((d.team = 2 AND d.lane = 1) OR (d.team = 3 AND d.lane = 3))
)
SELECT 'wave' AS row, pby, coalesce(CAST(okpos AS TEXT), 'none') AS okby, count(*) AS n,
    sum(coalesce(lever, '') LIKE '%pull%') AS chose,
    sum(coalesce(lever, '') NOT LIKE '%pull%' AND (rej LIKE '%pull:no_sup%' OR rej LIKE '%pull:away%' OR rej LIKE '%pull:stack%')) AS no_puller,
    sum(coalesce(lever, '') NOT LIKE '%pull%' AND (rej LIKE '%pull:no_sup%' OR rej LIKE '%pull:away%' OR rej LIKE '%pull:stack%')
        AND anyin AND rule <> 'R6') AS no_puller_in,
    round(avg(CASE WHEN own45 IS NOT NULL THEN abs(own45 - tgt) < abs(own - tgt) END), 2) AS nearer,
    NULL AS ok
FROM w GROUP BY pby, okby
UNION ALL
SELECT 'start', 'core', 'all', count(*), NULL, NULL, NULL, NULL, round(avg(p.res = 'ok'), 2)
FROM ev_pull_job p JOIN gm ON gm.game_id = p.game_id WHERE p.pos = 3
UNION ALL
SELECT 'start_died', 'core', 'all', sum(p.died), NULL, NULL, NULL, NULL, NULL
FROM ev_pull_job p JOIN gm ON gm.game_id = p.game_id WHERE p.pos = 3
ORDER BY 1, 2, 3;
