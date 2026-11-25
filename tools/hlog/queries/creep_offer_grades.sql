-- Grades of the lane creep offer's reads against what happened (master docs/proposals/2026-11-25-no-creep-unpaid.md s4a), over the lines
-- `q @creep_offers` selects (same params), a creep whose death is joined only. Errors are (death t - snap) in seconds less the read, so a
-- negative error is a creep that died sooner than the read said.
-- Rows `part` dies: the predicted `dies` (the seconds until the others' damage kills the creep, so a read of a death with no hero's hit) graded
-- only where no hero's hit came: want 1 lines with dies >= 0 whose death is `other` or `tower` (`how`), `key` that class; `n`, `q1`, `med`, `q3`
-- of the error (death t - snap) - dies. A creep a hero took is left out: the hero's hit is not in `dies`.
-- Rows `part` due: the error (death t - snap) - `due` (the seconds until a swing ordered then is due) for every want 1 line, `key` the fate
-- class: `hero` (a last hit or a deny, by either side), `other`, `tower`. `early` the lines with error < 0 (the creep died before the read said a
-- swing came due), `early5` those under -0.5; NULL on the other parts.
-- Rows `part` killer: the forecast killing hit `key` (`kb`: me, mate, foe, creep, tower, none) against the creep's fate `fate`: `me` this hero took it
-- (a last hit on theirs, a deny on ours), `mate` another hero of its team did, `foe` an enemy hero did (a last hit on ours, a deny on theirs), `other`
-- (a creep, a tower or a spell: no hero); and `unmatched` for the lines with no death joined. `n` the count.
-- Columns: part, key, fate, n, q1, med, q3, early, early5.
-- Params: as @creep_offers.
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
co_e AS (
    SELECT 'dies' AS part, o.how AS key, (o.dt - o.snap) - o.dies AS err
    FROM creep_offer_rows o WHERE o.matched AND o.want = 1 AND o.dies >= 0 AND o.how IN ('other', 'tower')
    UNION ALL
    SELECT 'due', CASE WHEN o.how IN ('lh', 'deny') THEN 'hero' ELSE o.how END, (o.dt - o.snap) - o.due
    FROM creep_offer_rows o WHERE o.matched AND o.want = 1 AND o.due IS NOT NULL
),
co_q AS (
    SELECT part, key, err, row_number() OVER (PARTITION BY part, key ORDER BY err) AS rn, count(*) OVER (PARTITION BY part, key) AS n FROM co_e
),
co_fate AS (
    SELECT o.kb,
        CASE WHEN NOT o.matched THEN 'unmatched' WHEN o.mine THEN 'me'
             WHEN o.how IN ('lh', 'deny') AND o.by_pid IS NOT NULL AND
                (SELECT b.team FROM ev_bot b WHERE b.game_id = o.game_id AND b.pid = o.by_pid LIMIT 1) = o.team THEN 'mate'
             WHEN o.how IN ('lh', 'deny') AND o.by_pid IS NOT NULL THEN 'foe' ELSE 'other' END AS fate
    FROM creep_offer_rows o
)
SELECT part, key, NULL AS fate, max(n) AS n, min(CASE WHEN rn = (n + 3) / 4 THEN round(err, 2) END) AS q1,
    round(avg(CASE WHEN rn IN ((n + 1) / 2, (n + 2) / 2) THEN err END), 2) AS med,
    min(CASE WHEN rn = (3 * n + 3) / 4 THEN round(err, 2) END) AS q3,
    CASE part WHEN 'due' THEN sum(err < 0) END AS early, CASE part WHEN 'due' THEN sum(err < -0.5) END AS early5
FROM co_q GROUP BY part, key
UNION ALL
SELECT 'killer', kb, fate, count(*), NULL, NULL, NULL, NULL, NULL FROM co_fate GROUP BY kb, fate
ORDER BY 1, 2, 3
