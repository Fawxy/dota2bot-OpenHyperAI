-- Fragment (`-- include: ep_job`): the one definition of a job trip. The including query defines `gm(game_id, ...)` first.
-- CTE `ep_job(game_id, pid, src, job, t0, t1, why)`: a started trip of one hero and the first end that follows it.
--   src    the log it is in: job (the chooser's stack, rune, pull, pullfarm and camp), lane_job (the older lane jobs, which
--          still run with the chooser off) or farm_trip
--   t1     NULL, with why, for a trip with no end before that hero's next start of the same one or the end of the log
-- A trip is a logged job. Stock logs none: a walk to a rune there is a stretch of mode rune. Ends with a comma.
-- ensure: ev_job(pid, job, phase, why)
-- ensure: ev_lane_job_start(pid, kind)
-- ensure: ev_lane_job_end(pid, reason)
-- ensure: ev_lane_job_abort(pid, reason)
-- ensure: ev_lane_job(pid, grade)
-- ensure: ev_farm_trip_start(pid)
-- ensure: ev_farm_trip_end(pid, why)
epj_e AS (
    SELECT game_id, seq, t, pid, 'job' AS src, job, job AS same, phase = 'start' AS st, why
    FROM ev_job WHERE game_id IN (SELECT game_id FROM gm) AND phase IN ('start', 'end')
    UNION ALL
    SELECT game_id, seq, t, pid, 'lane_job', kind, '', 1, NULL FROM ev_lane_job_start WHERE game_id IN (SELECT game_id FROM gm)
    UNION ALL
    SELECT game_id, seq, t, pid, 'lane_job', NULL, '', 0, reason FROM ev_lane_job_end WHERE game_id IN (SELECT game_id FROM gm)
    UNION ALL
    SELECT game_id, seq, t, pid, 'lane_job', NULL, '', 0, reason FROM ev_lane_job_abort WHERE game_id IN (SELECT game_id FROM gm)
    UNION ALL
    -- A completed lane pull has no end line: its graded `lane_job` line is the end.
    SELECT game_id, seq, t, pid, 'lane_job', NULL, '', 0, grade FROM ev_lane_job WHERE game_id IN (SELECT game_id FROM gm)
    UNION ALL
    SELECT game_id, seq, t, pid, 'farm_trip', 'farm', '', 1, NULL FROM ev_farm_trip_start WHERE game_id IN (SELECT game_id FROM gm)
    UNION ALL
    SELECT game_id, seq, t, pid, 'farm_trip', NULL, '', 0, why FROM ev_farm_trip_end WHERE game_id IN (SELECT game_id FROM gm)
),
epj_n AS (
    SELECT e.*, lead(e.st) OVER w AS next_st, lead(e.t) OVER w AS next_t, lead(e.why) OVER w AS next_why
    FROM epj_e e WINDOW w AS (PARTITION BY e.game_id, e.pid, e.src, e.same ORDER BY e.t, e.seq)
),
ep_job AS MATERIALIZED (
    SELECT game_id, pid, src, job, t AS t0, CASE WHEN next_st = 0 THEN next_t END AS t1,
        CASE WHEN next_st = 0 THEN next_why END AS why
    FROM epj_n WHERE st = 1
),
