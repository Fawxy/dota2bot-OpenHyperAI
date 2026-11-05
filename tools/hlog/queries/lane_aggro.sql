-- Lane aggro (slice lane-aggro): one row per game, move kind and role from `ev=aggro` (lane_aggro), to :until (default 600).
-- tries (every line), by result: denied (feed: our deny), ok (drag: our last hit), lost, alive, no_draw, hurt, died, cancelled;
-- drew (lines with drawn >= 1), mean drawn, onr_any (feed lines with an enemy creep on the fed creep after the drop), mean dhp
-- (HP lost per move). Per game beside it, the coverage: rn our ranged lane creeps that died before :until (both teams, every
-- lane: in these games every lineup bot runs our code) and rd those we denied (`ev=own_creep_death` `by` a pid).
-- Params: like (LIKE pattern on games.file), until.
-- ensure: ev_aggro(pid, kind, role, result, drawn, onr, dhp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
cov AS (
    SELECT d.game_id, count(*) AS rn, sum(d.by <> 'none') AS rd
    FROM ev_own_creep_death d JOIN gm ON gm.game_id = d.game_id
    WHERE d.kind = 'ranged' AND d.t < coalesce(:until, 600)
    GROUP BY d.game_id
)
SELECT gm.file, a.kind, a.role, count(*) AS tries,
    sum(a.result = 'denied') AS denied, sum(a.result = 'ok') AS ok, sum(a.result = 'lost') AS lost,
    sum(a.result = 'alive') AS alive, sum(a.result = 'no_draw') AS no_draw, sum(a.result = 'hurt') AS hurt,
    sum(a.result = 'died') AS died, sum(a.result = 'cancelled') AS cancelled,
    sum(a.drawn >= 1) AS drew, round(avg(a.drawn), 2) AS drawn, sum(a.onr >= 1) AS onr_any, round(avg(a.dhp), 1) AS dhp,
    cov.rn, cov.rd
FROM ev_aggro a JOIN gm ON gm.game_id = a.game_id LEFT JOIN cov ON cov.game_id = a.game_id
WHERE a.t < coalesce(:until, 600)
GROUP BY gm.file, a.kind, a.role
ORDER BY gm.file, a.kind, a.role;
