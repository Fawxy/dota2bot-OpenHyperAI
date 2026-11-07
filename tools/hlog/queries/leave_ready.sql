-- Leave-ready (slice lane-control 3, design s5.5 rule 1, s5.9): where a support's lane stands when the support leaves on a
-- stack or rune trip, in games whose file matches :like. One row per departure group (`job`) plus an `all` row:
--   n departures (ev_job phase=start, job stack or rune, a pos4/pos5 bot) with a lane decision read in the 30 s before;
--   at_ready the share whose lane, at the last ev=lane_ctl kind=wave read before the leave, had its clash (`own`) on our side
--   of the target plus LaneControl Band (150): own <= tgt + 150; after_ready the same at the first read 25 s or more after the
--   leave (one wave on, the core alone); both_ready both; mean_at, mean_after the clash past the target at each (own - tgt);
--   reset_share the departures whose lane had an R2 decision (the reset wave) in the 60 s before the leave. Grouped by
--   `pulled`: 1 when this support's own `ok` pull (ev=pull_job) had its slot in the 60 s before the leave.
-- The lane is the one whose decision names this support (`sup`), so a support already out of lane at the read has no row.
-- ensure: ev_lane_ctl(team, lane, kind, wave, own, tgt, sup, rule)
-- ensure: ev_job(job, phase, pid)
-- ensure: ev_pull_job(pid, slot, res)
-- ensure: ev_bot(pid, team, pos)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
sp AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE pos IN (4, 5) GROUP BY 1, 2),
dep AS MATERIALIZED (
    SELECT j.game_id, j.pid, j.job, j.t, sp.team
    FROM ev_job j JOIN gm ON gm.game_id = j.game_id JOIN sp ON sp.game_id = j.game_id AND sp.pid = j.pid
    WHERE j.phase = 'start' AND j.job IN ('stack', 'rune')
),
at AS MATERIALIZED (
    SELECT dep.*, (
        SELECT d.seq FROM ev_lane_ctl d
        WHERE d.game_id = dep.game_id AND d.team = dep.team AND d.kind = 'wave' AND d.sup = dep.pid AND d.own IS NOT NULL
            AND d.t <= dep.t AND d.t > dep.t - 30
        ORDER BY d.t DESC LIMIT 1) AS aseq
    FROM dep
),
r AS (
    SELECT at.job, a.own - a.tgt AS pa,
        (SELECT n.own - n.tgt FROM ev_lane_ctl n WHERE n.game_id = at.game_id AND n.team = at.team AND n.lane = a.lane
            AND n.kind = 'wave' AND n.own IS NOT NULL AND n.t >= at.t + 25 ORDER BY n.t LIMIT 1) AS pn,
        EXISTS (SELECT 1 FROM ev_lane_ctl x WHERE x.game_id = at.game_id AND x.team = at.team AND x.lane = a.lane
            AND x.kind = 'wave' AND x.rule = 'R2' AND x.t <= at.t AND x.t > at.t - 60) AS reset,
        EXISTS (SELECT 1 FROM ev_pull_job p WHERE p.game_id = at.game_id AND p.pid = at.pid AND p.res = 'ok'
            AND p.slot <= at.t AND p.slot > at.t - 60) AS pulled
    FROM at JOIN ev_lane_ctl a ON a.game_id = at.game_id AND a.seq = at.aseq
)
SELECT job, pulled, count(*) AS n,
    round(avg(pa <= 150), 2) AS at_ready,
    round(avg(CASE WHEN pn IS NOT NULL THEN pn <= 150 END), 2) AS after_ready,
    round(avg(CASE WHEN pn IS NOT NULL THEN pa <= 150 AND pn <= 150 END), 2) AS both_ready,
    round(avg(pa)) AS mean_at, round(avg(pn)) AS mean_after,
    round(avg(reset), 2) AS reset_share
FROM (SELECT * FROM r UNION ALL SELECT 'all' AS job, pa, pn, reset, pulled FROM r UNION ALL SELECT 'all' AS job, pa, pn, reset, 'all' FROM r)
GROUP BY job, pulled ORDER BY job = 'all', job, pulled;
