-- The turn rule as the half-pull harness measures it (slice pull-half): of the ev=pull_creep rows over the logs whose path
-- contains `batch` where no neutral was within the creep's own acquisition range (melee 500, ranged 600; EC-090), how many
-- turned onto a neutral per 50 of distance to the puller (dp), split by whether a tagged neutral was hitting the puller
-- (ph) and whether the puller stood still (pv under 50). A hero rule of radius R shows as turned = n below R and 0 above
-- it; no step shows no hero rule. Params: batch (substring of the log path).
-- ensure: ev_pull_creep(tr, dp, dn, rg, ph, pv)
SELECT (c.dp / 50) * 50 AS dp_from, c.ph, CASE WHEN c.pv < 50 THEN 1 ELSE 0 END AS still,
    count(*) AS n, sum(c.tr) AS turned, min(c.dn) AS dn_min
FROM ev_pull_creep c JOIN games g USING (game_id)
WHERE g.file LIKE '%' || :batch || '%'
  AND c.dp IS NOT NULL AND (c.dn IS NULL OR c.dn > CASE WHEN c.rg = 1 THEN 600 ELSE 500 END)
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
