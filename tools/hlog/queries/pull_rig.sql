-- The pull rig's read (families proposal s5 step 2): per game and lane wave of the pulling team, the wave's own creeps by where
-- they died, whether or not the wave was pulled. Games whose file matches :like; :team (default 2, the `pull` drill's Radiant).
-- A wave is our lane creeps of one lane born in the same 30 s (ev=wave_creep_death, floor(born / 30)); it is `pulled` when an
-- ev=pull_job of that team and lane names it (floor((slot - 1) / 30), as pull_line; its lane 1-3 is the wave line's top, mid,
-- bot), with the job's res and its stay's end (st).
--   n its creeps; at_camp those that died within 700 of a neutral camp's spawn point (pull_line's w_camp: they never got back
--   to lane); denied ours (`by` names one of our heroes); life the mean seconds from born to death.
-- Waves born before 55 s or from :to (default 580) are left out (a wave unfinished at a 10:00 end).
-- ensure: ev_wave_creep_death(team, kind, x, y, by, lane, born)
-- ensure: ev_pull_job(pid, lane, slot, res, st)
-- ensure: ev_bot(pid, team, pos)
WITH
-- include: camp_spawns
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE team IS NOT NULL AND game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
jobs AS (
    SELECT j.game_id, CASE j.lane WHEN 1 THEN 'top' WHEN 2 THEN 'mid' WHEN 3 THEN 'bot' END AS lane, CAST((j.slot - 1) / 30 AS INTEGER) AS wave, max(j.res) AS res, max(j.st) AS st
    FROM ev_pull_job j JOIN tm ON tm.game_id = j.game_id AND tm.pid = j.pid
    WHERE tm.team = coalesce(:team, 2) GROUP BY 1, 2, 3
),
deaths AS (
    SELECT w.game_id, w.lane, CAST(w.born / 30 AS INTEGER) AS wave, w.t - w.born AS life,
        CAST(w."by" AS TEXT) NOT IN ('none', '') AS denied,
        EXISTS (SELECT 1 FROM camps k WHERE (k.x - w.x) * (k.x - w.x) + (k.y - w.y) * (k.y - w.y) <= 490000) AS at_camp
    FROM ev_wave_creep_death w
    WHERE w.game_id IN (SELECT game_id FROM gm) AND w.team = coalesce(:team, 2) AND w.born >= 55 AND w.born < coalesce(:to, 580)
)
SELECT gm.file, d.lane, d.wave * 30 AS born, j.wave IS NOT NULL AS pulled, j.res, j.st, count(*) AS n, sum(d.at_camp) AS at_camp,
    sum(d.denied) AS denied, round(avg(d.life), 0) AS life
FROM deaths d JOIN gm ON gm.game_id = d.game_id
LEFT JOIN jobs j ON j.game_id = d.game_id AND j.lane = d.lane AND j.wave = d.wave
GROUP BY d.game_id, d.lane, d.wave ORDER BY gm.file, d.lane, d.wave
