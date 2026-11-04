-- Upper bound on what a job lean could save (slice lane-positioning step 3, plan 2026-11-03-lane-positioning s4): one row per
-- job kind, job starts (`ev=job phase=start`) :from to :until (default 60-600).
-- A lean can only move the hero's lane spot inside the spot's corridor, so at most it pre-walks the part of the trip that
-- stays there. Corridor seconds are counted from the start to the first later snapshot more than :width (default 250: the
-- spot's 200 sideways plus the support's 240 shift is near it) from the lane path (`ld`) or more than :back (default 1,000:
-- the spot's MAX_BACK) from where the hero stood at the start. Forward walking, the hard limits and the lane cost of standing
-- off the spot are all ignored, so the bound is loose.
--   starts      job starts;  in_lane  those whose snapshot nearest the start is within :width of the lane path
--   trip_s      mean seconds from start to the job's `phase=end` (all starts)
--   corr_s      mean corridor seconds over the in-lane starts, ending at the job's end when that comes first
--   per_trip    corridor seconds over all starts (an out-of-lane start or an open one counts 0): the plan's per-trip measure
--   ge2         in-lane starts with 2 s or more
--   open        in-lane starts with no exit snapshot within 45 s (left out of corr_s)
-- Params: like, from, until, width, back.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
st AS MATERIALIZED (
    SELECT j.game_id, j.pid, j.job, j.t AS t0,
        (SELECT min(e.t) FROM ev_job e WHERE e.game_id = j.game_id AND e.pid = j.pid AND e.job = j.job
            AND e.phase = 'end' AND e.t >= j.t) AS t1
    FROM ev_job j JOIN gm ON gm.game_id = j.game_id
    WHERE j.phase = 'start' AND j.t >= coalesce(:from, 60) AND j.t <= coalesce(:until, 600)
),
s AS MATERIALIZED (
    SELECT st.game_id, st.pid, st.t0, sn.t, sn.x, sn.y, sn.ld,
        row_number() OVER (PARTITION BY st.game_id, st.pid, st.t0 ORDER BY abs(sn.t - st.t0)) AS r
    FROM st JOIN ev_snap sn ON sn.game_id = st.game_id AND sn.pid = st.pid AND sn.t BETWEEN st.t0 - 1.5 AND st.t0 + 45
),
o AS (SELECT game_id, pid, t0, x AS ox, y AS oy, ld AS ld0 FROM s WHERE r = 1),
ex AS (
    SELECT s.game_id, s.pid, s.t0,
        min(CASE WHEN s.t > s.t0 AND (s.ld > coalesce(:width, 250)
            OR (s.x - o.ox) * (s.x - o.ox) + (s.y - o.oy) * (s.y - o.oy) > coalesce(:back, 1000) * coalesce(:back, 1000))
            THEN s.t END) AS tx
    FROM s JOIN o USING (game_id, pid, t0) GROUP BY 1, 2, 3
),
c AS (
    SELECT st.job, st.t1 - st.t0 AS trip, o.ld0 <= coalesce(:width, 250) AS inl,
        CASE WHEN st.t1 IS NOT NULL AND st.t1 < ex.tx THEN st.t1 ELSE ex.tx END - st.t0 AS corr
    FROM st JOIN o USING (game_id, pid, t0) JOIN ex USING (game_id, pid, t0)
)
SELECT job, count(*) AS starts, sum(inl) AS in_lane, round(avg(trip), 1) AS trip_s,
    round(avg(CASE WHEN inl THEN corr END), 1) AS corr_s,
    round(sum(CASE WHEN inl THEN coalesce(corr, 0) ELSE 0 END) * 1.0 / count(*), 1) AS per_trip,
    sum(CASE WHEN inl AND corr >= 2 THEN 1 ELSE 0 END) AS ge2,
    sum(CASE WHEN inl AND corr IS NULL THEN 1 ELSE 0 END) AS open
FROM c GROUP BY job ORDER BY job;
