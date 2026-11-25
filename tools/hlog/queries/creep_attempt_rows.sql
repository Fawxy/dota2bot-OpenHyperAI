-- The creep row's attempts, one row each (creep_row.ts `ev=job job=creep`; master docs/proposals/2026-11-25-no-creep-unpaid.md s5):
-- the start and end, the creep's death and the hero's deaths. Counted per game by @creep_attempts; the columns are fragment
-- creep_attempt_rows's (read its header).
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; pid.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_attempt_rows
SELECT gm.file, gm.game, a.team, a.pid, a.hero, a.pos, a.t0, a.t1, a.len, a.cid, a.gw, a.rng, a.melee, a.cls, a.why, a.cut, a.arr,
    a.tin, a.sw, a.swon, a.gap, a.dt, a.hp0, a.hp1, a.hplost, a.died, a.msg
FROM creep_attempt_rows a JOIN gm USING (game_id)
WHERE :pid IS NULL OR a.pid = :pid
ORDER BY gm.file, gm.game, a.t0, a.pid
