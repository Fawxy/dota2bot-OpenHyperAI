-- The creep row's attempts per game by outcome (creep_row.ts `ev=job job=creep`; master docs/proposals/2026-11-25-no-creep-unpaid.md
-- s5, the oha-creep-ranged re-read's table): one row per game, class (landed, cut, lost_swing, lost_inrange, lost_out, lost_nodeath),
-- the cutting mode and whether the hero had reached the verb's range first (`arr`: after, before; NULL on logs without `tin`).
-- Columns: n; melee (attempts by a hero of range under 300); swon (a swing of the hero on the creep as it died); sword (the verb
-- ordered its swing; NULL on cuts and older logs); gw (mean walk at go, s); gap (mean distance less range at the creep's death);
-- hplost (mean HP lost from start to end, the end line's or the snapshots'); died (attempts with the hero dead by 5 s past the end).
-- Also split by `ontime` (fragment: 1 when the start line's spare sp >= 0, 0 under, NULL on logs before it).
-- Also per game, one extra column per `fate` (fragment creep_attempt_rows: who was paid for the creep): self_row, self_other,
-- mate, deny, tower, unpaid, nodeath, and hero_paid (self_row + self_other), team_paid (hero_paid + mate), over the group's attempts.
-- One row per attempt: @creep_attempt_rows.
-- Params: like (a path fragment or run label) or batch (the exact run name; a label with no lineup letter has none, use like), one is required.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_attempt_rows
SELECT gm.file, gm.game, a.cls, a.cut, a.arr, a.ontime, count(*) AS n, sum(a.melee) AS melee, sum(coalesce(a.swon, 0)) AS swon,
    sum(a.sw) AS sword, round(avg(a.gw), 2) AS gw, round(avg(a.gap)) AS gap, round(avg(a.hplost)) AS hplost, sum(a.died) AS died,
    sum(a.fate = 'self_row') AS self_row, sum(a.fate = 'self_other') AS self_other, sum(a.fate = 'mate') AS mate, sum(a.fate = 'deny') AS deny,
    sum(a.fate = 'tower') AS tower, sum(a.fate = 'unpaid') AS unpaid, sum(a.fate = 'nodeath') AS nodeath,
    sum(a.fate IN ('self_row', 'self_other')) AS hero_paid, sum(a.fate IN ('self_row', 'self_other', 'mate')) AS team_paid
FROM creep_attempt_rows a JOIN gm USING (game_id)
GROUP BY gm.file, gm.game, a.cls, a.cut, a.arr, a.ontime
ORDER BY gm.file, gm.game,
    CASE a.cls WHEN 'landed' THEN 0 WHEN 'cut' THEN 1 WHEN 'lost_swing' THEN 2 WHEN 'lost_inrange' THEN 3 WHEN 'lost_out' THEN 4 ELSE 5 END,
    a.cut, a.arr, a.ontime
