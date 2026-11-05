-- Support pull farm (slice support-pull-farm, PullFarm, Ours.SupportPullFarm): one row per decision after an ok pull, in games
-- whose file matches :like. `start` rows carry their end line (the pid's next `phase=end`); `skip` rows the gate that held the farm
-- when its StartWithin window closed (or the claim that gave the camp to a core).
--   why        start: how it ended (back, interrupted:yield, interrupted:threat, ...); skip: core-coming, core-there, no-neutrals, late, ...
--   n0/nl      neutrals on the camp at the decision / left at the end; div the pull's diverted share then; ago seconds from the pull's end
--   gain       g1 - g0 less passive gold over the job (:passive a second, default 1.5); nk the hero's ev=neutral_death last hits from
--              start to end; died: a snapshot at 0 HP from start to end + 3 s
-- ensure: ev_pull_clear(pid, phase, camp, ago, div, n0, why, nl, back, g0, g1, secs, hp0, hp, died)
-- ensure: ev_neutral_death(team, by)
-- ensure: ev_snap(pid, hp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
st AS (SELECT c.* FROM ev_pull_clear c JOIN gm ON gm.game_id = c.game_id WHERE c.phase IN ('start', 'skip')),
row AS (
    SELECT st.game_id, st.pid, st.pos, st.t, st.phase, st.camp, st.ago, st.div, st.n0, st.why AS skip_why,
        (SELECT min(e.t) FROM ev_pull_clear e WHERE e.game_id = st.game_id AND e.pid = st.pid AND e.phase = 'end' AND e.t >= st.t AND st.phase = 'start') AS t1
    FROM st
)
SELECT gm.file, r.game_id, r.pid, r.pos, r.t, r.phase, r.camp, r.ago, r.div, r.n0,
    coalesce(e.why, r.skip_why) AS why, e.nl, e.back, e.secs, e.hp0, e.hp,
    round(e.g1 - e.g0 - coalesce(:passive, 1.5) * e.secs, 1) AS gain,
    (SELECT count(*) FROM ev_neutral_death d WHERE d.game_id = r.game_id AND CAST(d.by AS TEXT) = CAST(r.pid AS TEXT) AND d.t >= r.t AND d.t <= r.t1) AS nk,
    CASE WHEN r.phase = 'start' THEN (SELECT count(*) > 0 FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t >= r.t AND s.t <= r.t1 + 3 AND s.hp <= 0) END AS died
FROM row r JOIN gm ON gm.game_id = r.game_id
LEFT JOIN ev_pull_clear e ON e.game_id = r.game_id AND e.pid = r.pid AND e.phase = 'end' AND e.t = r.t1
ORDER BY r.game_id, r.t, r.pid;
