-- Fragment (`-- include: creep_fate_rows`): the one definition of a lane creep death's fate, view creep_fate's rows (its header
-- has the rule). The including query defines first, each `AS NOT MATERIALIZED` (each is read twice, and a copy of a store-wide
-- table would be slow), the creep deaths to read: `cf_enemy` the rows of ev_creep_death and `cf_own` those of
-- ev_own_creep_death, all columns, of the same games (view creep_fate: every game; the timeline: its own, so its cost follows
-- the games read). CTE `creep_fate_rows(game_id, seq, t, team, side, kind, x, y, fate, pid, tw)`. Ends with a comma.
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
cf_cand AS (
    SELECT c.game_id, c.seq AS cseq, o.seq AS oseq, o."by" AS denier,
        abs(o.t - c.t) AS dt, (o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y) AS d2
    FROM cf_enemy c
    JOIN cf_own o ON o.game_id = c.game_id AND o.team <> c.team AND o.kind = c.kind
        AND o.t BETWEEN c.t - 1.0 AND c.t + 1.0
        AND (o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y) <= 62500
    WHERE CAST(c."by" AS TEXT) = 'none' AND CAST(o."by" AS TEXT) <> 'none'
),
cf_by_c AS (
    SELECT *, row_number() OVER (PARTITION BY game_id, cseq ORDER BY d2, dt, oseq) AS rc FROM cf_cand
),
cf_by_o AS (
    SELECT *, row_number() OVER (PARTITION BY game_id, oseq ORDER BY d2, dt, cseq) AS ro FROM cf_by_c WHERE rc = 1
),
cf_pairs AS (
    SELECT game_id, cseq, denier FROM cf_by_o WHERE ro = 1
),
creep_fate_rows AS (
    SELECT c.game_id, c.seq, c.t, c.team, 'enemy' AS side, c.kind, c.x, c.y,
        CASE WHEN CAST(c."by" AS TEXT) NOT IN ('none', 'deny') THEN 'own_lh'
             WHEN p.cseq IS NOT NULL OR CAST(c."by" AS TEXT) = 'deny' THEN 'enemy_deny'
             ELSE 'other' END AS fate,
        CASE WHEN CAST(c."by" AS TEXT) NOT IN ('none', 'deny') THEN c."by" ELSE p.denier END AS pid,
        c.tw
    FROM cf_enemy c
    LEFT JOIN cf_pairs p ON p.game_id = c.game_id AND p.cseq = c.seq
    UNION ALL
    SELECT o.game_id, o.seq, o.t, o.team, 'own', o.kind, o.x, o.y,
        CASE WHEN CAST(o."by" AS TEXT) <> 'none' THEN 'own_deny' ELSE 'lost' END,
        CASE WHEN CAST(o."by" AS TEXT) <> 'none' THEN o."by" END,
        NULL
    FROM cf_own o
),
