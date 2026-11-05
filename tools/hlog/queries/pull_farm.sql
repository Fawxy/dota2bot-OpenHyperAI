-- Farm at a pull (slice lane-farm-logs; plan docs/proposals/2026-11-04-lane-stage-farm.md pieces 3 and 4): one row per `ok`
-- ev=pull_job in games whose file matches :like, with who took the camp's neutrals and the pulled wave. The rule and its
-- columns are fragment pull_farm's (shared with view pull_waves); :win is its neutral window (default 45 s, `judgement`).
WITH
-- include: camp_spawns
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
pfw(win) AS (SELECT coalesce(:win, 45)),
-- include: pull_farm
done AS (SELECT 1)
SELECT gm.file, r.game_id, r.team, r.pid, r.pos, r.camp, r.slot, r.n_ours, r.n_puller, r.n_none,
    r.own_died, r.own_denied, r.them_took, r.them_core
FROM pf_rows r JOIN gm ON gm.game_id = r.game_id
ORDER BY r.game_id, r.slot, r.pid;
