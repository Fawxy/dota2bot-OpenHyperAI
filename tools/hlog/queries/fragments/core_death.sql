-- Fragment (`-- include: core_death`): every death of a lineup core (pos 1-3) before :until (default 600) and what it was doing,
-- as @core_deaths reads them (its header has the rules). The including query defines `gm(game_id, file)` first. CTEs: s, d, last,
-- x, tw (enemy tower positions), c, and cd(game_id, pid, t, team, pos, hp, mode, activity, in_range, x, y, trade, cut, tower, cause).
-- Ends with a comma.
-- ensure: ev_trade(pid, kind, result, why, dur, hpd, thpd)
s AS (
    SELECT s.game_id, s.t, s.pid, s.deaths, lag(s.deaths) OVER w AS prev, lag(s.t) OVER w AS prev_t
    FROM ev_snap s JOIN gm ON gm.game_id = s.game_id JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
    WHERE l.pos <= 3 AND s.deaths IS NOT NULL
    WINDOW w AS (PARTITION BY s.game_id, s.pid ORDER BY s.seq)
),
d AS (SELECT game_id, pid, prev_t AS t FROM s WHERE prev IS NOT NULL AND deaths > prev AND prev_t < coalesce(:until, 600)),
last AS (
    SELECT d.game_id, d.pid, d.t,
        (SELECT a.seq FROM lane_activity a WHERE a.game_id = d.game_id AND a.pid = d.pid AND a.t <= d.t AND a.t >= d.t - 10 ORDER BY a.t DESC LIMIT 1) AS seq
    FROM d
),
x AS (
    SELECT l.game_id, l.pid, l.t, a.team, a.pos, a.hp, a.mode, a.activity, a.in_range, a.x, a.y,
        EXISTS (SELECT 1 FROM ev_trade tr WHERE tr.game_id = l.game_id AND tr.pid = l.pid AND tr.result IN ('done', 'kill')
            AND tr.t >= l.t - 10 AND tr.t - tr.dur <= l.t + 1) AS trade,
        EXISTS (SELECT 1 FROM lane_activity r JOIN lane_activity c ON c.game_id = r.game_id AND c.pid = r.pid AND c.t > r.t AND c.spike
            WHERE r.game_id = l.game_id AND r.pid = l.pid AND r.mode = 'retreat' AND r.t >= l.t - 10 AND c.t <= l.t) AS cut
    FROM last l LEFT JOIN lane_activity a ON a.game_id = l.game_id AND a.seq = l.seq
),
-- Tower positions (team, x, y): dynamic.js TOWERS (7.41, from validated pro replays); keep the two equal.
tw (team, x, y) AS (VALUES
    (2, -3952, -6112), (2, -4640, -4144), (2, -6592, -3408), (2, -360, -6256), (2, 4860, -6379), (2, -3190, -2926),
    (2, -6501, -872), (2, -6336, 1856), (2, -5712, -4864), (2, -5392, -5192), (2, -1544, -1408),
    (3, 4944, 4776), (3, -128, 6016), (3, -5275, 6036), (3, 2496, 2112), (3, 524, 652), (3, 6400, 384), (3, 6336, 3032),
    (3, 3552, 5776), (3, 4272, 3759), (3, 5280, 4432), (3, 6269, -2240)),
c AS (
    SELECT x.*, EXISTS (SELECT 1 FROM tw WHERE tw.team <> x.team AND (tw.x - x.x) * (tw.x - x.x) + (tw.y - x.y) * (tw.y - x.y) <= 900 * 900) AS tower
    FROM x
),
cd AS (
    SELECT c.*,
        CASE WHEN c.trade THEN 'trade' WHEN c.cut THEN 'cut' WHEN c.mode = 'retreat' THEN 'retreat' WHEN c.tower THEN 'tower'
             WHEN c.mode = 'laning' THEN 'lane' ELSE coalesce(c.mode, 'unknown') END AS cause
    FROM c
),
