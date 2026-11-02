-- The lane read against what the game did (slice lane-read): one row per game, lane, team and whole second, the team's
-- ev=lane_read joined with the other team's line for the same lane and second. A team always sees its own creeps, so the
-- other team's census is that team's creeps without fog.
-- adv_true: advantage over the same creeps near our front, with the enemy's own count of its creeps there (cnp) in place
--   of the ones we could see (ep). 550 is lane_config ForecastModel.PowerFloor, as in lane_read Advantage.
-- meet_err: map distance between the midpoint of the two teams' wave fronts (Valve's GetLaneFrontLocation, which lane_read
--   reads eq from) and where the creeps met (midpoint of the two lead creeps, whole lane); NULL when either side has no creep
--   in the lane. It checks the fronts, not eq itself: MeetAmount (which may use one front) and EqPos are checked in E0 only.
--   By map position, not lane amount: each team's script measures amounts along its own lane path, so the two teams'
--   amounts for one place differ (game lr1: Dire's 0.07-0.16 lower).
-- hp_lost, ehp_lost: own and enemy creep HP lost in the lane over the next 10 s; NULL unless the window ends before the next
--   spawn (cyc < 20), since a spawn adds HP.
-- ensure: ev_lane_read(team, lane, adv, eq, a, e, ap, ep, of, ef, ot, et, cyc, cn, chp, cpw, cl, clx, cly, cnn, cnp, fx, fy, ee)
WITH firsts AS (
    SELECT game_id, CAST(t AS INTEGER) AS sec, team, lane, min(seq) AS seq FROM ev_lane_read GROUP BY 1, 2, 3, 4
),
x AS MATERIALIZED (
    SELECT f.sec, l.* FROM firsts f JOIN ev_lane_read l ON l.game_id = f.game_id AND l.seq = f.seq
)
SELECT a.game_id, a.sec, a.team, a.lane, a.cyc,
    a.adv, 1.0 + (a.ap - b.cnp) * 1.0 / (a.ap + b.cnp + 550) AS adv_true,
    a.e AS e_seen, b.cnn AS e_true,
    a.eq,
    CASE WHEN a.cn > 0 AND b.cn > 0 AND a.clx IS NOT NULL AND b.clx IS NOT NULL
        THEN sqrt(((a.fx + b.fx) - (a.clx + b.clx)) * ((a.fx + b.fx) - (a.clx + b.clx))
                + ((a.fy + b.fy) - (a.cly + b.cly)) * ((a.fy + b.fy) - (a.cly + b.cly))) / 2.0 END AS meet_err,
    CASE WHEN a.cyc < 20 THEN a.chp - a2.chp END AS hp_lost,
    CASE WHEN a.cyc < 20 THEN b.chp - b2.chp END AS ehp_lost,
    a.fx, a.fy, a.ee
FROM x a
JOIN x b ON b.game_id = a.game_id AND b.sec = a.sec AND b.lane = a.lane AND b.team <> a.team
LEFT JOIN x a2 ON a2.game_id = a.game_id AND a2.team = a.team AND a2.lane = a.lane AND a2.sec = a.sec + 10
LEFT JOIN x b2 ON b2.game_id = a.game_id AND b2.team = b.team AND b2.lane = a.lane AND b2.sec = a.sec + 10
