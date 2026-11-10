-- The retreat drills' stop grade (slice retreat-gone, master docs/team/slices/2026-11-10-retreat-gone.md): one row per our
-- episode (ev=retreat kind=ours) that ended, with its tail: seconds from the last second an enemy hero was in reach of the
-- hero (fragment lane_rules' lr_f en_r: its attack range + 600) to the end, or from the start when none was. The right
-- action is a tail of 1 s or less (the snapshot second's rounding and the read's 0.1 s cadence).
--   why, res, secs, hp0       the start's reason, how it ended, its length, HP share at the start
--   tail, reached              the tail; 1 when an enemy was in reach at some second of it
--   rep                        the drill rep (Drill.RepAt: every 60 s from 60) the episode started in, for chase drills
-- Params: like (file pattern), until (start time cap, default 720).
-- ensure: ev_retreat(ph, pid, kind, ep, why, hp, res)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
rt_ep AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.ep, s.t AS t0, s.why, s.hp AS hp0, e.t AS t1, e.res
    FROM ev_retreat s JOIN gm USING (game_id)
    JOIN ev_retreat e ON e.game_id = s.game_id AND e.pid = s.pid AND e.ep = s.ep AND e.ph = 'end' AND e.kind = 'ours'
    WHERE s.ph = 'start' AND s.kind = 'ours' AND s.t <= coalesce(:until, 720)
),
rt_last AS (
    SELECT ep.game_id, ep.pid, ep.ep,
        (SELECT max(f.sec) FROM lr_f f WHERE f.game_id = ep.game_id AND f.pid = ep.pid AND f.sec >= ep.t0 - 0.5 AND f.sec <= ep.t1 + 0.5 AND f.en_r > 0) AS last
    FROM rt_ep ep
)
SELECT gm.file, ep.pid, round(ep.t0, 1) AS t, ep.why, ep.res, round(ep.t1 - ep.t0, 1) AS secs, ep.hp0,
    round(max(0, ep.t1 - coalesce(l.last, ep.t0)), 1) AS tail, l.last IS NOT NULL AS reached,
    CAST(ep.t0 / 60 AS INTEGER) AS rep
FROM rt_ep ep JOIN rt_last l USING (game_id, pid, ep) JOIN gm USING (game_id)
ORDER BY gm.file, ep.t0
