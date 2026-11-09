-- retreat-linger windows (slice retreat, master docs/team/specs/2026-11-10-retreat-read-bars.md): one row per
-- `ev=drill ph=linger` in games whose file matches :like, its start joined to its `ph=linger_end` by (game, chaser pid, rep).
--   rep, t0, thp, d, res, secs_to_contact, dmin, clamp   the window as the chaser logged it (secs only when res is contact)
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
-- Params: like (file pattern; null = all). The cast is the `ph=linger` line's `tpid`; a window with no end line runs 20 s.
-- ensure: ev_drill(ph, name, pid, rep, tpid, thp, d, res, secs, dmin, clamp)
-- ensure: ev_lane_pos(pid, why, rb, rm, mp, op, rp)
-- ensure: ev_retreat(ph, pid, kind, ep)
WITH
gm AS MATERIALIZED (SELECT game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
st AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.tpid, d.rep, d.t, d.thp, d.d
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'linger'
),
en AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.rep, d.t, d.res, d.secs, d.dmin, d.clamp
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'linger_end'
),
win AS MATERIALIZED (
    SELECT st.game_id, st.pid, st.tpid, st.rep, st.t AS t0, st.thp, st.d,
        coalesce(en.t, st.t + 20) AS t1, en.res, en.secs, en.dmin, en.clamp
    FROM st LEFT JOIN en ON en.game_id = st.game_id AND en.pid = st.pid AND en.rep = st.rep AND en.t >= st.t
)
SELECT gm.file, w.rep, round(w.t0, 1) AS t0, w.thp, w.d, w.res,
    CASE WHEN w.res = 'contact' THEN w.secs END AS secs_to_contact, w.dmin, w.clamp,
    (SELECT coalesce(sum(a.hp - b.hp), 0) FROM ev_snap a JOIN ev_snap b ON b.game_id = a.game_id AND b.pid = a.pid
        AND b.t = (SELECT min(c.t) FROM ev_snap c WHERE c.game_id = a.game_id AND c.pid = a.pid AND c.t > a.t)
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.t0 AND b.t <= w.t1 AND b.hit = 1 AND b.hp < a.hp) AS hpl,
    (SELECT coalesce(max(a.lh) - min(a.lh), 0) FROM ev_snap a
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.t0 AND a.t <= w.t1) AS lh,
    (SELECT coalesce(max(a.dn) - min(a.dn), 0) FROM ev_snap a
     WHERE a.game_id = w.game_id AND a.pid = w.tpid AND a.t >= w.t0 AND a.t <= w.t1) AS dn,
    (SELECT count(*) FROM ev_retreat s WHERE s.game_id = w.game_id AND s.pid = w.tpid AND s.kind = 'ours' AND s.ph = 'start' AND s.t <= w.t0
        AND NOT EXISTS (SELECT 1 FROM ev_retreat e WHERE e.game_id = s.game_id AND e.pid = s.pid AND e.ep = s.ep AND e.ph = 'end' AND e.t <= w.t0)) AS ep,
    (SELECT count(*) FROM ev_retreat e WHERE e.game_id = w.game_id AND e.pid = w.tpid AND e.kind = 'ours' AND e.ph = 'end'
        AND e.t > w.t0 AND e.t <= w.t1) AS epend,
    (SELECT max(l.rb) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1) AS rb,
    (SELECT max(l.rm) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1) AS rm,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1
        AND (',' || l.mp || ',') LIKE '%,' || w.pid || ',%') AS unseen,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1
        AND l.why = 'xp') AS xp,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1
        AND l.rp IN ('burst', 'missing') AND l.op = 'none') AS rpush,
    (SELECT count(*) FROM ev_lane_pos l WHERE l.game_id = w.game_id AND l.pid = w.tpid AND l.t >= w.t0 AND l.t <= w.t1
        AND l.op <> 'none' AND l.rp = 'none') AS opush
FROM win w JOIN gm USING (game_id)
ORDER BY gm.file, w.t0
