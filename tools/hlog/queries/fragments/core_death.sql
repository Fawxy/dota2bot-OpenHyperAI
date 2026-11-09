-- Fragment (`-- include: core_death`): every death of a lineup core (pos 1-3, or :pos_lo to :pos_hi) before :until (default 600) and what it was doing,
-- as @core_deaths reads them (its header has the rules). The including query defines `gm(game_id, file)` first. CTEs: s0-s4, s, d, last,
-- x, tw (enemy tower positions), c, and cd(game_id, pid, t, team, pos, hp, mode, activity, in_range, x, y, trade, cut, tower, cause).
-- Ends with a comma.
-- ensure: ev_trade(pid, kind, result, why, dur, hpd, thpd)
s0 AS (
    SELECT s.game_id, s.seq, s.t, s.pid, s.deaths, s.x, s.y, s.hp,
        ((s.x + 6700) * (s.x + 6700) + (s.y + 6700) * (s.y + 6700) <= 1200 * 1200
            OR (s.x - 6928) * (s.x - 6928) + (s.y - 6372) * (s.y - 6372) <= 1200 * 1200) AS nearf
    FROM ev_snap s JOIN gm ON gm.game_id = s.game_id JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
    WHERE l.pos >= coalesce(:pos_lo, 1) AND l.pos <= coalesce(:pos_hi, 3) AND s.deaths IS NOT NULL
),
-- The death count rises only at the first snap after the respawn, and the snaps before it are not the hero's last living moment
-- (the frozen run): a killed hero logs a few snaps with hp 0 where it fell (hp is a whole percent), and some also 1-5 snaps at
-- its fountain with hp rising from 0, then none for the respawn wait. jump_from is the time of the last real snap when a snap
-- lands at a fountain more than 1,200 from the one before it; last_ok is the last snap with hp above 0.
s1 AS (
    SELECT s0.*, lag(s0.deaths) OVER w AS prev, lag(s0.t) OVER w AS prev_t, lag(s0.nearf) OVER w AS prev_nearf,
        CASE WHEN s0.nearf AND s0.t - lag(s0.t) OVER w < 3
            AND (s0.x - lag(s0.x) OVER w) * (s0.x - lag(s0.x) OVER w) + (s0.y - lag(s0.y) OVER w) * (s0.y - lag(s0.y) OVER w) > 1200 * 1200
            THEN lag(s0.t) OVER w END AS jump_from
    FROM s0
    WINDOW w AS (PARTITION BY s0.game_id, s0.pid ORDER BY s0.seq)
),
s2 AS (
    SELECT s1.*, max(CASE WHEN s1.hp > 0 THEN s1.t END) OVER (PARTITION BY s1.game_id, s1.pid ORDER BY s1.t) AS last_ok
    FROM s1
),
-- jump_ok: the last snap with hp above 0 before the jump (the snap before it can itself read hp 0).
s3 AS (
    SELECT s2.*, CASE WHEN s2.jump_from IS NOT NULL THEN lag(s2.last_ok) OVER w END AS jump_ok FROM s2
    WINDOW w AS (PARTITION BY s2.game_id, s2.pid ORDER BY s2.seq)
),
s4 AS (
    SELECT s3.*, min(s3.jump_ok) OVER (PARTITION BY s3.game_id, s3.pid ORDER BY s3.t RANGE BETWEEN 8 PRECEDING AND CURRENT ROW) AS jt FROM s3
),
s AS (
    SELECT s4.*, lag(s4.jt) OVER w AS prev_jt, lag(s4.last_ok) OVER w AS prev_ok FROM s4
    WINDOW w AS (PARTITION BY s4.game_id, s4.pid ORDER BY s4.seq)
),
d AS (
    SELECT game_id, pid, t FROM (
        SELECT game_id, pid, CASE WHEN prev_ok >= c - 15 THEN min(prev_ok, c) ELSE c END AS t
        FROM (SELECT s.*, CASE WHEN prev_nearf AND prev_jt IS NOT NULL THEN prev_jt ELSE prev_t END AS c FROM s) s
        WHERE prev IS NOT NULL AND deaths > prev
    ) WHERE t < coalesce(:until, 600)
),
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
