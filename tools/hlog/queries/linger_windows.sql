-- retreat-linger windows (slice retreat, master docs/team/specs/2026-11-10-retreat-read-bars.md): one row per
-- `ev=drill ph=linger_go` (the HP trigger) in games whose file matches :like, joined to its `ph=linger` (t0: the chaser first
-- stands at the stand-off, the window's clock; null when it never did) and `ph=linger_end` by (game, chaser pid, rep).
--   rep, tgo, t0, thp, dgo, res, secs_to_contact (from t0), dmin, dmax, dend, clamp   the window as the chaser logged it
--   ctl       seconds of the window past the chase rep's end (`rend`): the control rep's chaser is out, not waiting behind its T1, so
--             grade a control rep only after its window ends
--   hpl       HP-% lost in the cast's snap seconds flagged `hit` inside the window (the slice's truth: only one enemy hero is
--             active in this drill, and `hph` misses chaser damage)
--   lh, dn    the cast's last hits and denies in the window
--   ep        an episode (`ev=retreat kind=ours`) running at t0
--   epend     episodes ended inside the window (the rtwatch1 shape proper)
--   rb, rm    the highest read burst and missing at the chosen spot on the cast's `ev=lane_pos` rows in the window
--   unseen    lane_pos frames whose `mp` holds the chaser's pid
--   xp        lane_pos frames with why=xp
--   rpush     frames whose read verdict at the preferred point (`rp`) breaks while the old limits' (`op`) is none: pushed by the read only
--   opush     the reverse: pushed by the old limits only
-- Params: like (file pattern; null = all). The cast is the line's `tpid`.
-- ensure: ev_drill(ph, name, pid, rep, tpid, thp, d, res, secs, dmin, dmax, dend, clamp, rend)
-- ensure: ev_lane_pos(pid, why, rb, rm, mp, op, rp)
-- ensure: ev_retreat(ph, pid, kind, ep)
WITH
gm AS MATERIALIZED (SELECT game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
go AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.tpid, d.rep, d.t AS tg, d.thp, d.d AS dgo, d.rend
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'linger_go'
),
win AS MATERIALIZED (
    SELECT go.*,
        (SELECT min(s.t) FROM ev_drill s WHERE s.game_id = go.game_id AND s.pid = go.pid AND s.ph = 'linger' AND s.rep = go.rep AND s.t >= go.tg) AS t0,
        (SELECT min(e.t) FROM ev_drill e WHERE e.game_id = go.game_id AND e.pid = go.pid AND e.ph = 'linger_end' AND e.rep = go.rep AND e.t >= go.tg) AS te
    FROM go
),
w2 AS MATERIALIZED (
    SELECT win.*, coalesce(win.t0, win.tg) AS ta, coalesce(win.te, coalesce(win.t0, win.tg) + 20) AS t1,
        (SELECT e.res FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS res,
        (SELECT e.secs FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS secs,
        (SELECT e.dmin FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS dmin,
        (SELECT e.dmax FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS dmax,
        (SELECT e.dend FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS dend,
        (SELECT e.clamp FROM ev_drill e WHERE e.game_id = win.game_id AND e.pid = win.pid AND e.ph = 'linger_end' AND e.t = win.te LIMIT 1) AS clamp
    FROM win
)
SELECT gm.file, w.rep, round(w.tg, 1) AS tgo, round(w.t0, 1) AS t0, w.thp, w.dgo, w.res,
    CASE WHEN w.res = 'contact' THEN w.secs END AS secs_to_contact, w.dmin, w.dmax, w.dend, w.clamp,
    round(max(0, w.t1 - w.rend), 1) AS ctl,
    (SELECT coalesce(sum(a.hp - b.hp), 0) FROM ev_snap a JOIN ev_snap b ON b.game_id = a.game_id AND b.pid = a.pid
        AND b.t = (SELECT min(c.t) FROM ev_snap c WHERE c.game_id = a.game_id AND c.pid = a.pid AND c.t > a.t)
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.ta AND b.t <= w.t1 AND b.hit = 1 AND b.hp < a.hp) AS hpl,
    (SELECT coalesce(max(a.lh) - min(a.lh), 0) FROM ev_snap a
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.ta AND a.t <= w.t1) AS lh,
    (SELECT coalesce(max(a.dn) - min(a.dn), 0) FROM ev_snap a
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.ta AND a.t <= w.t1) AS dn,
    (SELECT count(*) FROM ev_retreat s WHERE s.game_id = w.game_id AND s.pid = w.tpid AND s.kind = 'ours' AND s.ph = 'start' AND s.t <= w.ta
        AND NOT EXISTS (SELECT 1 FROM ev_retreat e WHERE e.game_id = s.game_id AND e.pid = s.pid AND e.ep = s.ep AND e.ph = 'end' AND e.t <= w.ta)) AS ep,
    (SELECT count(*) FROM ev_retreat e WHERE e.game_id = w.game_id AND e.pid = w.tpid AND e.kind = 'ours' AND e.ph = 'end'
        AND e.t > w.ta AND e.t <= w.t1) AS epend,
    (SELECT max(l.rb) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1) AS rb,
    (SELECT max(l.rm) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1) AS rm,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1
        AND (',' || l.mp || ',') LIKE '%,' || w.pid || ',%') AS unseen,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1 AND l.why = 'xp') AS xp,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1
        AND l.rp IN ('burst', 'missing') AND l.op = 'none') AS rpush,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.ta AND l.t <= w.t1
        AND l.op <> 'none' AND l.rp = 'none') AS opush
FROM w2 w JOIN gm USING (game_id)
ORDER BY gm.file, w.tg
