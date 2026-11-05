-- Fragment (`-- include: pull_farm`): who took the camp's neutrals and the pulled wave per `ok` ev=pull_job (slice
-- lane-farm-logs; query @pull_farm and view pull_waves). Reads the CTEs `camps` (fragment camp_spawns), `gm(game_id, file)`
-- (the games to read) and `pfw(win)` (the neutral window in seconds) the including SQL defines first. Defines `pf_bots`,
-- `pf_pulls` and `pf_rows`, one row per `ok` pull (game_id, seq, team, pid, pos, camp, slot and the columns below). Ends with a comma.
-- Every window runs from the planned hit second (`slot`) up to, not including, the earlier of its own end and the next ok pull
--   of the same team on the same camp (back-to-back pulls 25-30 s apart would otherwise count one death twice).
-- n_*: the pulling team's ev=neutral_death at that camp (`camp` index), window slot + win: `n_ours` by any of its heroes,
--   `n_puller` by the puller, `n_none` no one's (the pulled wave's, a hero of the other team, or a neutral that left vision at
--   half HP or less, which ev=creep_revive names afterwards). Null on builds before neutral_death (no row of it in the game)
--   and for a slot after Telemetry.CreepDeathUntil (720 s), when nothing is logged.
-- own_*: the pulled wave, from the pulling team's ev=own_creep_death within 800 of the camp's spawn, window slot + 30 (as
--   @lane_waste's `pulled`): `own_died` logged deaths, `own_denied` its own denies.
-- them_*: the same creeps in the other team's log (ev=creep_death, logged only within 1,500 of one of its heroes): `them_took`
--   their last hits, `them_core` those by their pos 1-3 (a core at the enemy's pull).
-- ensure: ev_neutral_death(team, camp, by)
-- ensure: ev_own_creep_death(team, x, y, by)
-- ensure: ev_creep_death(team, x, y, by)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_pull_job(pid, pos, camp, slot, res)
pf_bots AS (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
pf_ok AS (
    SELECT j.game_id, j.seq, j.pid, b.team, j.pos, j.camp, j.slot, c.x AS cx, c.y AS cy
    FROM ev_pull_job j JOIN pf_bots b ON b.game_id = j.game_id AND b.pid = j.pid
    JOIN camps c ON c.idx = j.camp
    WHERE j.game_id IN (SELECT game_id FROM gm) AND j.res = 'ok'
),
pf_pulls AS (
    SELECT *, coalesce(lead(slot) OVER (PARTITION BY game_id, team, camp ORDER BY slot, seq), 1e9) AS next_slot FROM pf_ok
),
pf_logged AS (SELECT DISTINCT game_id FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
pf_n AS (
    SELECT p.game_id, p.seq,
        sum(CAST(d.by AS TEXT) <> 'none') AS n_ours,
        sum(CAST(d.by AS TEXT) = CAST(p.pid AS TEXT)) AS n_puller,
        sum(CAST(d.by AS TEXT) = 'none') AS n_none
    FROM pf_pulls p JOIN ev_neutral_death d ON d.game_id = p.game_id AND d.team = p.team AND d.camp = p.camp
        AND d.t >= p.slot AND d.t < min(p.slot + (SELECT win FROM pfw), p.next_slot)
    GROUP BY 1, 2
),
pf_own AS (
    SELECT p.game_id, p.seq, count(*) AS own_died, sum(CAST(o.by AS TEXT) <> 'none') AS own_denied
    FROM pf_pulls p JOIN ev_own_creep_death o ON o.game_id = p.game_id AND o.team = p.team
        AND o.t >= p.slot AND o.t < min(p.slot + 30, p.next_slot)
        AND (o.x - p.cx) * (o.x - p.cx) + (o.y - p.cy) * (o.y - p.cy) <= 800 * 800
    GROUP BY 1, 2
),
pf_them AS (
    SELECT p.game_id, p.seq,
        sum(CAST(c.by AS TEXT) NOT IN ('none', 'deny')) AS them_took,
        sum(b.pos BETWEEN 1 AND 3) AS them_core
    FROM pf_pulls p JOIN ev_creep_death c ON c.game_id = p.game_id AND c.team <> p.team
        AND c.t >= p.slot AND c.t < min(p.slot + 30, p.next_slot)
        AND (c.x - p.cx) * (c.x - p.cx) + (c.y - p.cy) * (c.y - p.cy) <= 800 * 800
    LEFT JOIN pf_bots b ON b.game_id = c.game_id AND CAST(b.pid AS TEXT) = CAST(c.by AS TEXT)
    GROUP BY 1, 2
),
pf_rows AS (
    SELECT p.game_id, p.seq, p.team, p.pid, p.pos, p.camp, p.slot,
        CASE WHEN l.game_id IS NULL OR p.slot > 720 THEN NULL ELSE coalesce(n.n_ours, 0) END AS n_ours,
        CASE WHEN l.game_id IS NULL OR p.slot > 720 THEN NULL ELSE coalesce(n.n_puller, 0) END AS n_puller,
        CASE WHEN l.game_id IS NULL OR p.slot > 720 THEN NULL ELSE coalesce(n.n_none, 0) END AS n_none,
        coalesce(own.own_died, 0) AS own_died, coalesce(own.own_denied, 0) AS own_denied,
        coalesce(them.them_took, 0) AS them_took, coalesce(them.them_core, 0) AS them_core
    FROM pf_pulls p
    LEFT JOIN pf_logged l ON l.game_id = p.game_id
    LEFT JOIN pf_n n ON n.game_id = p.game_id AND n.seq = p.seq
    LEFT JOIN pf_own own ON own.game_id = p.game_id AND own.seq = p.seq
    LEFT JOIN pf_them them ON them.game_id = p.game_id AND them.seq = p.seq
),
