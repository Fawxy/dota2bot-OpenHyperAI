-- The wave hold (slice core-in-lane, states/wave_hold, Ours.CoreHold): its targets and coverage in games whose file matches :like.
-- One row per `br` (hold, drag, retreat) of ev=wave_hold: `n` attempts, `lh_share` the mean per attempt of our last hits over
-- their creeps at the start (lh / n), and the ends `met cleared tower hurt left died timeout`, `tw` attempts whose wave reached
-- our T1's range, `sw` attempts that changed branch. Then two coverage rows (`br` cover_pull, cover_tower): `n` diverted ok
-- pulls whose wave was under our T1 by 30 s (view pull_waves tw30 = 1), or lane-aggro tower moves by a core that drew their
-- creeps out (ev=aggro kind=tower result=ok); `missed` those with no ev=wave_hold of that team and lane (pulls) or that pid
-- (tower moves) starting in the 30 s from the slot or the move's line. A hold's start is its line's t less `dur`.
-- ensure: ev_wave_hold(pid, lane, br, res, n, lh, tw, sw, dur)
-- ensure: ev_aggro(pid, role, kind, result)
-- ensure: ev_bot(pid, team, pos)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
h AS MATERIALIZED (
    SELECT w.game_id, w.pid, tm.team, w.lane, w.br, w.res, w.n, w.lh, w.tw, w.sw, w.t - coalesce(w.dur, 0) AS t0
    FROM ev_wave_hold w JOIN tm ON tm.game_id = w.game_id AND tm.pid = w.pid
    WHERE w.game_id IN (SELECT game_id FROM gm)
),
pw AS (SELECT game_id, team, lane, slot FROM pull_waves WHERE grp = 'ok_div' AND tw30 = 1 AND game_id IN (SELECT game_id FROM gm)),
tw AS (SELECT game_id, pid, t FROM ev_aggro WHERE kind = 'tower' AND result = 'ok' AND role = 'core' AND game_id IN (SELECT game_id FROM gm))
SELECT br, count(*) AS n, round(avg(1.0 * lh / max(n, 1)), 2) AS lh_share,
    sum(res = 'met') AS met, sum(res = 'cleared') AS cleared, sum(res = 'tower') AS tower, sum(res = 'hurt') AS hurt,
    sum(res = 'left') AS "left", sum(res = 'died') AS died, sum(res = 'timeout') AS timeout, sum(tw = 1) AS tw, sum(sw > 0) AS sw,
    NULL AS missed
FROM h GROUP BY br
UNION ALL
SELECT 'cover_pull', count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    coalesce(sum(NOT EXISTS (SELECT 1 FROM h WHERE h.game_id = pw.game_id AND h.team = pw.team AND h.lane = pw.lane AND h.t0 >= pw.slot AND h.t0 <= pw.slot + 30)), 0)
FROM pw
UNION ALL
SELECT 'cover_tower', count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    coalesce(sum(NOT EXISTS (SELECT 1 FROM h WHERE h.game_id = tw.game_id AND h.pid = tw.pid AND h.t0 >= tw.t AND h.t0 <= tw.t + 30)), 0)
FROM tw;
