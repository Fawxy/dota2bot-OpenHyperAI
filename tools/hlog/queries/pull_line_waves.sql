-- pull_line by wave (families proposal s5, lanecamp's stack-and-pull group): per game, team, lane and wave of our own lane
-- creeps (born before :to, default 525), how the camp stood and what became of the wave. Games whose file matches :like.
-- pull_line.js reads it for the strong-camp split: an on game's waves pulled into a camp of at least --strong neutrals, against
-- the same team, lane and wave of its paired off game (pulled or not, wanted or not).
--   wanted  the team's pull trigger wanted the wave (ev=choice kind=pull want=1, its own line or a src=shadow one; wave
--           floor((slot - 1) / 30), as pull_line)
--   cn      the most neutrals that trigger's lines saw in the camp at the wave (`cn`, null where none was read; 0 with `cs` 0,
--           a camp out of sight: the trigger reads about 10 s before its slot, so a camp nobody watches reads 0, pullchain1)
--   diverted an ev=pull_job of the team on the wave with res ok and dt (or div) at least 0.75, as pull_line
--   nn      the most neutrals that diverted pull met (`nn`); null with no diverted pull
--   w_n, w_lh, w_lh_core, w_deny, w_tower, w_other, w_camp  the wave's creeps by fate, as pull_line (fragment wave_fate)
-- ensure: ev_choice(pid, kind, want, lane, slot, cn)
-- ensure: ev_pull_job(pid, lane, slot, res, div, dt, nn)
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_wave_creep_death(team, kind, x, y, by, lane, born)
WITH
-- include: camp_spawns
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot WHERE team IS NOT NULL AND game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
-- include: wave_fate
ch AS (
    SELECT c.game_id, tm.team, c.lane, CAST((c.slot - 1) / 30 AS INTEGER) AS wave, max(c.want = 1) AS wanted, max(c.cn) AS cn
    FROM ev_choice c JOIN tm ON tm.game_id = c.game_id AND tm.pid = c.pid
    WHERE c.kind = 'pull' GROUP BY 1, 2, 3, 4
),
jb AS (
    SELECT j.game_id, tm.team, j.lane, CAST((j.slot - 1) / 30 AS INTEGER) AS wave, max(j.nn) AS nn
    FROM ev_pull_job j JOIN tm ON tm.game_id = j.game_id AND tm.pid = j.pid
    WHERE j.res = 'ok' AND coalesce(j.dt, j.div) >= 0.75 GROUP BY 1, 2, 3, 4
)
SELECT f.game_id, g.file, f.team, f.lane, f.wave, coalesce(c.wanted, 0) AS wanted, c.cn, j.wave IS NOT NULL AS diverted, j.nn,
    count(*) AS w_n, sum(f.fate = 'lh') AS w_lh, sum(f.fate = 'lh' AND f.pos BETWEEN 1 AND 3) AS w_lh_core, sum(f.fate = 'deny') AS w_deny,
    sum(f.fate = 'tower') AS w_tower, sum(f.fate = 'other') AS w_other, sum(f.camp) AS w_camp
FROM wfate f JOIN gm g ON g.game_id = f.game_id
LEFT JOIN ch c ON c.game_id = f.game_id AND c.team = f.team AND c.lane = f.lane AND c.wave = f.wave
LEFT JOIN jb j ON j.game_id = f.game_id AND j.team = f.team AND j.lane = f.lane AND j.wave = f.wave
WHERE f.wave * 30 < coalesce(:to, 525)
GROUP BY f.game_id, f.team, f.lane, f.wave
ORDER BY g.file, f.team, f.lane, f.wave
