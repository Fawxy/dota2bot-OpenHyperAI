-- The lane read against what the game did (slice lane-read): one row per game, lane, team and whole second, the team's
-- ev=lane_read joined with the other team's line for the same lane and second. A team always sees its own creeps, so the
-- other team's census is that team's creeps without fog.
-- adv_true: advantage over the same creeps near our front, with the enemy's own count of its creeps there (cnp) in place
--   of the ones we could see (ep). 550 is lane_config ForecastModel.PowerFloor, as in lane_read Advantage.
-- eq_true: the meeting point as the midpoint of the two lead creeps (whole lane), on the same tower scale as eq; NULL when
--   either side has no creep in the lane.
-- hp_lost, ehp_lost: own and enemy creep HP lost in the lane over the next 10 s; NULL unless the window ends before the next
--   spawn (cyc < 20), since a spawn adds HP.
-- ensure: ev_lane_read(team, lane, adv, eq, a, e, ap, ep, of, ef, ot, et, cyc, cn, chp, cpw, cl, cnn, cnp, fx, fy, ee)
WITH firsts AS (
    SELECT game_id, CAST(t AS INTEGER) AS sec, team, lane, min(seq) AS seq FROM ev_lane_read GROUP BY 1, 2, 3, 4
),
x AS (
    SELECT f.sec, l.* FROM firsts f JOIN ev_lane_read l ON l.game_id = f.game_id AND l.seq = f.seq
)
SELECT a.game_id, a.sec, a.team, a.lane, a.cyc,
    a.adv, 1.0 + (a.ap - b.cnp) * 1.0 / (a.ap + b.cnp + 550) AS adv_true,
    a.e AS e_seen, b.cnn AS e_true,
    a.eq,
    CASE WHEN a.cn > 0 AND b.cn > 0 AND a.et <> a.ot
        THEN max(-1.0, min(1.0, 2.0 * ((a.cl + b.cl) / 2.0 - a.ot) / (a.et - a.ot) - 1)) END AS eq_true,
    CASE WHEN a.cyc < 20 THEN a.chp - a2.chp END AS hp_lost,
    CASE WHEN a.cyc < 20 THEN b.chp - b2.chp END AS ehp_lost,
    a.fx, a.fy, a.ee
FROM x a
JOIN x b ON b.game_id = a.game_id AND b.sec = a.sec AND b.lane = a.lane AND b.team <> a.team
LEFT JOIN x a2 ON a2.game_id = a.game_id AND a2.team = a.team AND a2.lane = a.lane AND a2.sec = a.sec + 10
LEFT JOIN x b2 ON b2.game_id = a.game_id AND b2.team = b.team AND b2.lane = a.lane AND b2.sec = a.sec + 10
