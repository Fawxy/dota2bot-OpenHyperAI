-- The creep row's attempts, one row each (creep_row.ts `ev=job job=creep`; master docs/proposals/2026-11-25-no-creep-unpaid.md s5):
-- the start and end, the creep's death and the hero's deaths. Counted per game by @creep_attempts; the columns are fragment
-- creep_attempt_rows's (read its header), with who was paid for the creep (`paid`, `mpos`), whether the attempt began with a walk
-- (`walkin`) and the attempt's `fate`, which the row's own `cls`/`why` undercounts: a row that ended not ok can still have last-hit.
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; pid.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_attempt_rows
SELECT gm.file, gm.game, a.team, a.pid, a.hero, a.pos, a.t0, a.t1, a.len, a.cid, a.gw, a.rng, a.melee, a.cls, a.why, a.cut, a.arr,
    a.tin, a.wt, a.pw, a.pq, a.ps, a.hc, a.sw, a.swon, a.gap, a.dt, a.hp0, a.hp1, a.hplost, a.died, a.paid, a.mpos, a.walkin, a.fate, a.gn, a.sp, a.ontime, a.hw, a.hm, a.hs, a.sa, a.nw, a.msg
FROM creep_attempt_rows a JOIN gm USING (game_id)
WHERE :pid IS NULL OR a.pid = :pid
ORDER BY gm.file, gm.game, a.t0, a.pid
