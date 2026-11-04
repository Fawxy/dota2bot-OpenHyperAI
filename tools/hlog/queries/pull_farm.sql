-- Farm at a pull (slice lane-farm-logs; plan docs/proposals/2026-11-04-lane-stage-farm.md pieces 3 and 4): one row per `ok`
-- ev=pull_job in games whose file matches :like, with who took the camp's neutrals and the pulled wave.
-- n_*: the pulling team's ev=neutral_death at that camp (`camp` index) from the planned hit second (`slot`) to slot + :win
--   (default 45 s, `judgement`): `n_ours` by any of its heroes, `n_puller` by the puller, `n_none` no one's (the pulled wave's,
--   or a hero of the other team). Null on builds before neutral_death (no row of it in the game).
-- own_*: the pulled wave, from the pulling team's ev=own_creep_death within 800 of the camp's spawn, slot to slot + 30 (as
--   @lane_waste's `pulled`): `own_died` logged deaths, `own_denied` its own denies.
-- them_*: the same creeps in the other team's log (ev=creep_death, logged only within 1,500 of one of its heroes): `them_took`
--   their last hits, `them_core` those by their pos 1-3 (piece 4, a core at the enemy's pull).
-- ensure: ev_neutral_death(team, camp, by)
-- ensure: ev_own_creep_death(team, x, y, by)
-- ensure: ev_creep_death(team, x, y, by)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_pull_job(pid, pos, camp, slot, res)
WITH
-- include: camp_spawns
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
bots AS (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
pulls AS (
    SELECT j.game_id, j.seq, j.pid, b.team, j.pos, j.camp, j.slot, c.x AS cx, c.y AS cy
    FROM ev_pull_job j JOIN bots b ON b.game_id = j.game_id AND b.pid = j.pid
    JOIN camps c ON c.idx = j.camp
    WHERE j.game_id IN (SELECT game_id FROM gm) AND j.res = 'ok'
),
logged AS (SELECT DISTINCT game_id FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
n AS (
    SELECT p.game_id, p.seq,
        sum(CAST(d.by AS TEXT) <> 'none') AS n_ours,
        sum(CAST(d.by AS TEXT) = CAST(p.pid AS TEXT)) AS n_puller,
        sum(CAST(d.by AS TEXT) = 'none') AS n_none
    FROM pulls p JOIN ev_neutral_death d ON d.game_id = p.game_id AND d.team = p.team AND d.camp = p.camp
        AND d.t BETWEEN p.slot AND p.slot + coalesce(:win, 45)
    GROUP BY 1, 2
),
own AS (
    SELECT p.game_id, p.seq, count(*) AS own_died, sum(CAST(o.by AS TEXT) <> 'none') AS own_denied
    FROM pulls p JOIN ev_own_creep_death o ON o.game_id = p.game_id AND o.team = p.team
        AND o.t BETWEEN p.slot AND p.slot + 30
        AND (o.x - p.cx) * (o.x - p.cx) + (o.y - p.cy) * (o.y - p.cy) <= 800 * 800
    GROUP BY 1, 2
),
them AS (
    SELECT p.game_id, p.seq,
        sum(CAST(c.by AS TEXT) NOT IN ('none', 'deny')) AS them_took,
        sum(b.pos BETWEEN 1 AND 3) AS them_core
    FROM pulls p JOIN ev_creep_death c ON c.game_id = p.game_id AND c.team <> p.team
        AND c.t BETWEEN p.slot AND p.slot + 30
        AND (c.x - p.cx) * (c.x - p.cx) + (c.y - p.cy) * (c.y - p.cy) <= 800 * 800
    LEFT JOIN bots b ON b.game_id = c.game_id AND CAST(b.pid AS TEXT) = CAST(c.by AS TEXT)
    GROUP BY 1, 2
)
SELECT gm.file, p.game_id, p.team, p.pid, p.pos, p.camp, p.slot,
    CASE WHEN l.game_id IS NULL THEN NULL ELSE coalesce(n.n_ours, 0) END AS n_ours,
    CASE WHEN l.game_id IS NULL THEN NULL ELSE coalesce(n.n_puller, 0) END AS n_puller,
    CASE WHEN l.game_id IS NULL THEN NULL ELSE coalesce(n.n_none, 0) END AS n_none,
    coalesce(own.own_died, 0) AS own_died, coalesce(own.own_denied, 0) AS own_denied,
    coalesce(them.them_took, 0) AS them_took, coalesce(them.them_core, 0) AS them_core
FROM pulls p JOIN gm ON gm.game_id = p.game_id
LEFT JOIN logged l ON l.game_id = p.game_id
LEFT JOIN n ON n.game_id = p.game_id AND n.seq = p.seq
LEFT JOIN own ON own.game_id = p.game_id AND own.seq = p.seq
LEFT JOIN them ON them.game_id = p.game_id AND them.seq = p.seq
ORDER BY p.game_id, p.slot, p.pid;
