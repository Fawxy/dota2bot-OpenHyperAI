-- Core camp trips (slice core-next-gold, CoreCamp, Ours.CoreCampTrip): one row per `ev=core_camp phase=start` in games whose
-- file matches :like, with its end line (the pid's next `phase=end`).
--   ret/back   planned return and the arrival second (null when the trip did not walk back); back_ok: back <= ret + 5
--   gain       g1 - g0 (net worth, so a purchase on the way is no loss) less passive gold over the trip (:passive a second, default 1.5: the commonest 10 s gold rise in
--              sspotchk1 is 15); paid: gain > the start line's forecast `loss`
--   nk         the hero's ev=neutral_death last hits from start to end; died: a snapshot at 0 HP from start to end + 3 s
-- ensure: ev_core_camp(pid, phase, camp, type, clash, ret, gold, loss, net, why, back, g0, g1, secs, camps)
-- ensure: ev_neutral_death(team, by)
-- ensure: ev_snap(pid, hp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
st AS (SELECT c.* FROM ev_core_camp c JOIN gm ON gm.game_id = c.game_id WHERE c.phase = 'start'),
trip AS (
    SELECT st.game_id, st.pid, st.pos, st.t, st.camp, st.type, st.clash, st.ret, st.gold, st.loss, st.net,
        (SELECT min(e.t) FROM ev_core_camp e WHERE e.game_id = st.game_id AND e.pid = st.pid AND e.phase = 'end' AND e.t >= st.t) AS t1
    FROM st
)
SELECT gm.file, p.game_id, p.pid, p.pos, p.t, p.camp, p.type, p.clash, p.ret, p.loss, e.why, e.camps, e.back,
    CASE WHEN e.back IS NOT NULL AND e.back <= p.ret + 5 THEN 1 ELSE 0 END AS back_ok,
    round(e.g1 - e.g0 - coalesce(:passive, 1.5) * e.secs, 1) AS gain,
    CASE WHEN e.g1 - e.g0 - coalesce(:passive, 1.5) * e.secs > p.loss THEN 1 ELSE 0 END AS paid,
    (SELECT count(*) FROM ev_neutral_death d WHERE d.game_id = p.game_id AND CAST(d.by AS TEXT) = CAST(p.pid AS TEXT) AND d.t >= p.t AND d.t <= p.t1) AS nk,
    (SELECT count(*) > 0 FROM ev_snap s WHERE s.game_id = p.game_id AND s.pid = p.pid AND s.t >= p.t AND s.t <= p.t1 + 3 AND s.hp <= 0) AS died
FROM trip p JOIN gm ON gm.game_id = p.game_id
LEFT JOIN ev_core_camp e ON e.game_id = p.game_id AND e.pid = p.pid AND e.phase = 'end' AND e.t = p.t1
ORDER BY p.game_id, p.t, p.pid;
