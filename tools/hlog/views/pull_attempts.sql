-- One row per started pull (ev=pull_job; slice support-lane) with the lane reading that started it and the lane after it.
-- diverted: div >= 0.75 (S.3: at least 3 of a 4-creep wave seen on a neutral during the watch). eq0, eq30, eq60: the
-- puller's team's lane `eq` from ev=lane_read (-1 at our T1, +1 at theirs; read from the two fronts) at the planned hit second
-- and 30 and 60 s later; d30, d60 its move (negative: towards our tower, what a pull is for). st, q, mv, cf: the choice's
-- push reading (cf: the model's move with our walking wave removed, to compare with d30).
-- needs: ev_pull_job(pid, pos, lane, camp, slot, res, why, label, div, n, left, away, died, hit, idle, wd, nn)
-- needs: ev_choice(pid, kind, go, want, why, lane, slot, st, q, mv, cf, tw, ms)
-- ensure: ev_lane_read(team, lane, eq)
-- ensure: ev_bot(pid, team, pos)
WITH tm AS (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE team IS NOT NULL GROUP BY game_id, pid),
p AS (
    SELECT p.*, tm.team,
        (SELECT r.eq FROM ev_lane_read r WHERE r.game_id = p.game_id AND r.team = tm.team AND r.lane = p.lane AND r.t >= p.slot ORDER BY r.t LIMIT 1) AS eq0,
        (SELECT r.eq FROM ev_lane_read r WHERE r.game_id = p.game_id AND r.team = tm.team AND r.lane = p.lane AND r.t >= p.slot + 30 ORDER BY r.t LIMIT 1) AS eq30,
        (SELECT r.eq FROM ev_lane_read r WHERE r.game_id = p.game_id AND r.team = tm.team AND r.lane = p.lane AND r.t >= p.slot + 60 ORDER BY r.t LIMIT 1) AS eq60
    FROM ev_pull_job p LEFT JOIN tm ON tm.game_id = p.game_id AND tm.pid = p.pid
)
SELECT p.game_id, g.file, g.game, p.t, p.pid, p.team, p.pos, p.lane, p.camp, p.slot, p.res, p.why, p.label, p.div, p.n, p.left, p.away, p.wd, p.nn,
    coalesce(p.died, 0) AS died, coalesce(p.hit, 0) AS hit,
    CASE WHEN p.div >= 0.75 THEN 1 ELSE 0 END AS diverted,
    c.st, c.q, c.mv, c.cf, c.tw, c.ms,
    p.eq0, p.eq30, p.eq60, p.eq30 - p.eq0 AS d30, p.eq60 - p.eq0 AS d60
FROM p JOIN games g USING (game_id)
LEFT JOIN ev_choice c ON c.game_id = p.game_id AND c.pid = p.pid AND c.kind = 'pull' AND c.go = 1 AND c.slot = p.slot
