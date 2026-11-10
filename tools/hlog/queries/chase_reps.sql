-- retreat-linger chase reps (slice retreat, master docs/team/specs/2026-11-10-retreat-read-engaged.md): one row per chase rep
-- (`ev=drill ph=rep input=on`) of a retreat-linger game whose file matches :like (null = all), for the cast (the `ph=role role=cast`
-- hero). A rep runs from its start to the next rep's start (60 s without one). Both arms (read on, old limits) read on one truth.
--   low      the cast's lowest HP (%) in the rep
--   trig     the linger trigger (`ph=linger_go`) fired in the rep; tgo its time
--   hpl_pre  HP-% lost in snap seconds flagged `hit` from the rep's start to the trigger (the whole rep with none)
--   hit_secs seconds from the first to the last hit-flag snap in that stretch (the hit phase: hpl_pre / hit_secs is the rate)
--   lh, dn   last hits and denies the cast made in the rep
--   rpush    lane_pos frames in the rep at snap HP over 80 whose read verdict at the preferred point (`rp`) is not `none`
--            (full-HP frames the read pushed; the lone-harasser decision wants these not to rise)
--   re       lane_pos frames in the rep with `re` (engaged heroes at the chosen spot's read) above 0
-- ensure: ev_drill(ph, name, pid, team, role, rep, input, start)
-- ensure: ev_lane_pos(pid, rp, re)
WITH
gm AS MATERIALIZED (
    SELECT g.game_id, g.file FROM games g WHERE g.file LIKE coalesce(:like, '%')
      AND EXISTS (SELECT 1 FROM ev_drill d WHERE d.game_id = g.game_id AND d.ph = 'role' AND d.name = 'retreat-linger')
),
casth AS MATERIALIZED (
    SELECT d.game_id, d.pid FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'role' AND d.role = 'cast'
),
reps AS MATERIALIZED (
    SELECT d.game_id, d.rep, d.start AS t0,
        coalesce((SELECT min(n.start) FROM ev_drill n WHERE n.game_id = d.game_id AND n.ph = 'rep' AND n.rep = d.rep + 1), d.start + 60) AS t1
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'rep' AND d.input = 'on' AND d.team = 2 GROUP BY d.game_id, d.rep
),
r2 AS MATERIALIZED (
    SELECT reps.game_id, reps.rep, reps.t0, reps.t1, casth.pid,
        (SELECT min(g.t) FROM ev_drill g WHERE g.game_id = reps.game_id AND g.ph = 'linger_go' AND g.rep = reps.rep) AS tgo
    FROM reps JOIN casth USING (game_id)
),
r3 AS MATERIALIZED (SELECT r2.*, coalesce(r2.tgo, r2.t1) AS te FROM r2)
SELECT gm.file, r.rep, r.t0 AS start,
    (SELECT min(s.hp) FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t >= r.t0 AND s.t < r.t1) AS low,
    CASE WHEN r.tgo IS NULL THEN 0 ELSE 1 END AS trig, round(r.tgo, 1) AS tgo,
    (SELECT coalesce(sum(a.hp - b.hp), 0) FROM ev_snap a JOIN ev_snap b ON b.game_id = a.game_id AND b.pid = a.pid
        AND b.t = (SELECT min(c.t) FROM ev_snap c WHERE c.game_id = a.game_id AND c.pid = a.pid AND c.t > a.t)
     WHERE a.game_id = r.game_id AND a.pid = r.pid AND a.t >= r.t0 AND b.t <= r.te AND b.hit = 1 AND b.hp < a.hp) AS hpl_pre,
    (SELECT round(coalesce(max(s.t) - min(s.t), 0), 1) FROM ev_snap s
     WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t >= r.t0 AND s.t <= r.te AND s.hit = 1) AS hit_secs,
    (SELECT coalesce(max(s.lh) - min(s.lh), 0) FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t >= r.t0 AND s.t < r.t1) AS lh,
    (SELECT coalesce(max(s.dn) - min(s.dn), 0) FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t >= r.t0 AND s.t < r.t1) AS dn,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = r.game_id AND l.pid = r.pid AND l.t >= r.t0 AND l.t < r.t1
        AND l.rp IN ('burst', 'missing')
        AND (SELECT s.hp FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.t >= l.t - 0.5 AND s.t < l.t + 0.5 LIMIT 1) > 80) AS rpush,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = r.game_id AND l.pid = r.pid AND l.t >= r.t0 AND l.t < r.t1 AND l.re > 0) AS re
FROM r3 r JOIN gm USING (game_id)
ORDER BY gm.file, r.rep
