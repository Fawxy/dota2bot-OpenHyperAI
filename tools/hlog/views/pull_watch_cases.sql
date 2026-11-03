-- One row per pull that ended ok (pull_attempts; a failed pull rarely reaches the watch) with what ev=pull_watch saw (slice support-lane open item: waves at the meet point
-- with neutrals near that never hit one). arrival: the first sample with our wave within 300 of the meet point; a_*: that
-- sample's fields (nd the nearest neutral to our creeps there, nh its distance from its camp origin, nt its target, nn
-- neutrals within 1200 of the meet point, won our creeps on a neutral, pd the puller to the meet point). mwon: the most of our
-- creeps on a neutral in any sample; mnd: the nearest any neutral came to our creeps; ntc: samples with a neutral on a creep.
-- cause (500: creep acquisition range, EC-053): diverted; no-wave (our wave never within 300 of the meet point while
-- sampled); no-neutral (none within the search); home (the nearest neutral within 400 of its camp and over 500 from our
-- creeps: it never followed or went back); apart (over 500 from our creeps, away from its camp); near-no-fight (within 500,
-- no creep of ours on it at any sample); partial (some of ours fought, under the diverted share).
-- needs: ev_pull_job(pid, slot, res)
-- needs: ev_choice(pid, kind, slot)
-- needs: ev_pull_watch(pid, slot, ph, wc, won, whe, wcr, wid, wd, nn, ntp, ntc, ntx, nd, nh, nt, pd)
WITH w AS (
    SELECT game_id, pid, slot, count(*) AS samples, max(won) AS mwon, min(nd) AS mnd,
        sum(CASE WHEN ntc > 0 THEN 1 ELSE 0 END) AS ntc,
        min(CASE WHEN wd <= 300 THEN t END) AS arrival
    FROM ev_pull_watch GROUP BY game_id, pid, slot
),
a AS (
    SELECT w.*, x.ph AS a_ph, x.nd AS a_nd, x.nh AS a_nh, x.nt AS a_nt, x.nn AS a_nn, x.won AS a_won, x.wc AS a_wc, x.pd AS a_pd
    FROM w LEFT JOIN ev_pull_watch x ON x.game_id = w.game_id AND x.pid = w.pid AND x.slot = w.slot AND x.t = w.arrival
)
SELECT p.game_id, p.t, p.pid, p.team, p.lane, p.camp, p.slot, p.res, p.why, p.diverted, p.div, p.dt, p.d30,
    a.samples, a.arrival, a.arrival - p.slot AS arr_after, a.a_ph, a.a_wc, a.a_won, a.a_nn, a.a_nd, a.a_nh, a.a_nt, a.a_pd,
    a.mwon, a.mnd, a.ntc,
    CASE WHEN p.diverted = 1 THEN 'diverted'
        WHEN a.arrival IS NULL THEN 'no-wave'
        WHEN a.a_nd IS NULL THEN 'no-neutral'
        WHEN a.a_nd > 500 AND a.a_nh <= 400 THEN 'home'
        WHEN a.a_nd > 500 THEN 'apart'
        WHEN coalesce(a.mwon, 0) = 0 THEN 'near-no-fight'
        ELSE 'partial' END AS cause
FROM pull_attempts p LEFT JOIN a ON a.game_id = p.game_id AND a.pid = p.pid AND a.slot = p.slot
WHERE p.res = 'ok'
