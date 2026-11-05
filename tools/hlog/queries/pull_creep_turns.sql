-- The half-pull harness's per-creep lines (ev=pull_creep, slice pull-half) over every log whose path contains `batch`:
-- one row per lane creep of ours near a half pull's watch after the hit, read at its turn onto a neutral (tr 1) or at its
-- nearest approach to the puller (tr 0). `src` names what could have turned it: `creep` when the nearest neutral was within
-- the creep's own acquisition range (melee 500, ranged 600; EC-090) and `hero` when only the puller was near enough for
-- a hero rule to apply; the puller's state in that frame: ph hit by a tagged neutral, pv its speed, po its distance off the
-- lane path, ca the creep's distance along the lane past the meet point. Params: batch (substring of the log path).
-- ensure: ev_pull_creep(pid, slot, camp, ci, rg, tr, tt, dp, dn, ph, pv, po, ca)
SELECT substr(g.file, instr(g.file, '-ph') + 1) AS log, c.camp, c.slot, c.ci, c.rg, c.tr,
    CASE WHEN c.dn IS NOT NULL AND c.dn <= CASE WHEN c.rg = 1 THEN 600 ELSE 500 END THEN 'creep' ELSE 'hero' END AS src,
    c.tt, c.dp, c.dn, c.ph, c.pv, c.po, c.ca
FROM ev_pull_creep c JOIN games g USING (game_id)
WHERE g.file LIKE '%' || :batch || '%'
ORDER BY g.file, c.slot, c.ci
