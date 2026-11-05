-- Core camp gates (slice core-next-gold): the laning seconds an owned core's trip planner held, by what held it, from the
-- per-minute `ev=core_camp phase=gates` tallies, by position, in games whose file matches :like. `secs` is every counted
-- planning second (one a second from 2:00); `fit` the seconds a camp fitted (a skip or a start).
-- ensure: ev_core_camp(phase, pos, pid, h_dead, h_mode, h_hp, h_far, h_wave, h_camp, h_fc, h_clash, h_gap, h_plan, h_skip, h_trip)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
g AS (SELECT c.* FROM ev_core_camp c JOIN gm ON gm.game_id = c.game_id WHERE c.phase = 'gates')
SELECT pos, count(DISTINCT game_id || ':' || pid) AS cores,
    sum(coalesce(h_dead, 0) + coalesce(h_mode, 0) + coalesce(h_hp, 0) + coalesce(h_far, 0) + coalesce(h_wave, 0) + coalesce(h_camp, 0)
        + coalesce(h_fc, 0) + coalesce(h_clash, 0) + coalesce(h_gap, 0) + coalesce(h_plan, 0) + coalesce(h_skip, 0) + coalesce(h_trip, 0)) AS secs,
    sum(coalesce(h_dead, 0)) AS dead, sum(coalesce(h_mode, 0)) AS mode, sum(coalesce(h_hp, 0)) AS low_hp, sum(coalesce(h_far, 0)) AS far,
    sum(coalesce(h_wave, 0)) AS wave, sum(coalesce(h_camp, 0)) AS no_camp, sum(coalesce(h_fc, 0)) AS no_fc,
    sum(coalesce(h_clash, 0)) AS no_clash, sum(coalesce(h_gap, 0)) AS gap, sum(coalesce(h_plan, 0)) AS no_plan,
    sum(coalesce(h_skip, 0) + coalesce(h_trip, 0)) AS fit
FROM g GROUP BY pos ORDER BY pos;
