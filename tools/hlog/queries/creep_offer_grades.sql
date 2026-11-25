-- Two grades of the lane creep offer's reads against what happened (master docs/proposals/2026-11-25-no-creep-unpaid.md s4a), over the lines
-- `q @creep_offers` selects (same params), a creep whose death is joined only.
-- Rows `part` dies: the predicted `dies` against the real death, for want 1 lines with dies >= 0: the error `(death t - snap) - dies` (s; negative
-- when the creep died sooner than read) by `key`, the walk bucket (0, to1: up to 1 s, to2: 1 to 2 s, over2); `n`, `q1`, `med`, `q3`.
-- Rows `part` killer: the forecast killing hit `key` (`kb`: me, mate, foe, creep, tower, none) against the creep's fate `fate`: `me` this hero took it
-- (a last hit on theirs, a deny on ours), `mate` another hero of its team did, `foe` an enemy hero did (a last hit on ours, a deny on theirs), `other`
-- (a creep, a tower or a spell: no hero); and `unmatched` for the lines with no death joined. `n` the count.
-- Columns: part, key, fate, n, q1, med, q3.
-- Params: as @creep_offers.
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
co_e AS (
    SELECT o.*, (o.dt - o.snap) - o.dies AS err,
        CASE WHEN o.walk = 0 THEN '0' WHEN o.walk <= 1 THEN 'to1' WHEN o.walk <= 2 THEN 'to2' ELSE 'over2' END AS wb
    FROM creep_offer_rows o WHERE o.matched AND o.want = 1 AND o.dies >= 0
),
co_q AS (
    SELECT wb, err, row_number() OVER (PARTITION BY wb ORDER BY err) AS rn, count(*) OVER (PARTITION BY wb) AS n FROM co_e
),
co_fate AS (
    SELECT o.kb,
        CASE WHEN NOT o.matched THEN 'unmatched' WHEN o.mine THEN 'me'
             WHEN o.how IN ('lh', 'deny') AND o.by_pid IS NOT NULL AND
                (SELECT b.team FROM ev_bot b WHERE b.game_id = o.game_id AND b.pid = o.by_pid LIMIT 1) = o.team THEN 'mate'
             WHEN o.how IN ('lh', 'deny') AND o.by_pid IS NOT NULL THEN 'foe' ELSE 'other' END AS fate
    FROM creep_offer_rows o
)
SELECT 'dies' AS part, wb AS key, NULL AS fate, max(n) AS n, min(CASE WHEN rn = (n + 3) / 4 THEN round(err, 2) END) AS q1,
    round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN err END), 2) AS med,
    min(CASE WHEN rn = (3 * n + 3) / 4 THEN round(err, 2) END) AS q3
FROM co_q GROUP BY wb
UNION ALL
SELECT 'killer', kb, fate, count(*), NULL, NULL, NULL FROM co_fate GROUP BY kb, fate
ORDER BY 1, 2, 3
