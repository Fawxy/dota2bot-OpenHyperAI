-- Does swinging uphill matter? The lane creep offer's lines on their creeps (`who=t`), counted by whether the hero attacks with a projectile
-- (`ra` above 320, as the engine reads it) and where its stand spot lies against the creep (`GetHeightLevel` of the spot and the creep,
-- `sh` and `ch`): below the creep (an uphill swing), level with it, above it, or unknown (a log with no heights, or the API gave none).
-- Columns: arm, proj (1 ranged, 0 melee), spot (below, level, above, unknown), n (lines), atk (lines where the hero was attacking the creep),
-- took (of those, the creep's last hit was this hero's: `mine`), took_pct (took over atk, per cent).
-- Rows are @creep_offers's (header there; fragment creep_offer_rows); params as it: like or batch required; from, until, back, fwd; comma
-- lists ck, who, pid, hero (who is always t here). Pool heroes only after splitting them: a hero's range, damage and lane differ.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
SELECT r.arm, o.proj AS proj,
    CASE WHEN o.sh IS NULL OR o.ch IS NULL THEN 'unknown' WHEN o.sh < o.ch THEN 'below' WHEN o.sh = o.ch THEN 'level' ELSE 'above' END AS spot,
    count(*) AS n, coalesce(sum(o.atk), 0) AS atk, coalesce(sum(o.atk = 1 AND o.mine = 1), 0) AS took,
    round(100.0 * sum(o.atk = 1 AND o.mine = 1) / nullif(sum(o.atk), 0), 1) AS took_pct
FROM creep_offer_rows o JOIN gm USING (game_id)
LEFT JOIN run_label r USING (game_id)
WHERE o.who = 't'
GROUP BY r.arm, o.proj, spot
ORDER BY r.arm, o.proj DESC, spot
