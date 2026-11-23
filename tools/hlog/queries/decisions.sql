-- Our decisions (ev=choice) by outcome and reason per batch, arm and side, each with its share.
-- One row per (batch, arm, side, what, outcome, why); share is of its (batch, arm, side, what) total, so the unwanted
-- opportunities are the denominator in the same table.
-- The rows are timeline_rows' kind `decision` (one per opportunity, from `ev=choice`; any choice kind but `shadow` and
-- `decider` shows here with no change to hlog). outcome: unwanted, off (a switched-off puller's shadow line that wanted it),
-- refused, done, cut, no_end, no_start; why: unwanted and refused the choice's reason, cut the trip's end reason.
-- Not comparable across arms as is: a shadow line's unwanted reason is `off` (it stands for `lane` and `no-read`), and an arm
-- with no seat (`off`) has side NULL, both teams together; `games` says how many games each row's group read.
-- Params: batch (exact run name) or like (a path fragment or one log), one is required; arm, from, to (seconds or m:ss),
-- lane; what (a choice kind, default all). game, hero, pid and kind are timeline_rows' own: leave them out.
WITH
-- include: timeline_rows
dec AS (
    SELECT file, game, batch, arm, side, what, outcome, why FROM timeline_rows
    WHERE kind = 'decision' AND (:what IS NULL OR what = :what)
)
SELECT batch, arm, side, what, outcome, why, count(*) AS n,
    round(1.0 * count(*) / sum(count(*)) OVER (PARTITION BY batch, arm, side, what), 3) AS share,
    (SELECT count(DISTINCT d2.file || ' ' || d2.game) FROM dec d2
        WHERE d2.batch IS d.batch AND d2.arm IS d.arm AND d2.side IS d.side AND d2.what = d.what) AS games
FROM dec d
GROUP BY batch, arm, side, what, outcome, why
ORDER BY batch, arm, side, what,
    CASE outcome WHEN 'unwanted' THEN 0 WHEN 'off' THEN 1 WHEN 'refused' THEN 2 WHEN 'no_start' THEN 3 WHEN 'done' THEN 4
        WHEN 'cut' THEN 5 ELSE 6 END, n DESC, why
