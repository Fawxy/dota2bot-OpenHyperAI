-- Lane-wide waste by cause (slice support-lane): per game and logging team, enemy lane creep deaths before :until (default 600)
-- in games whose file matches :like. `deaths` all logged enemy-side deaths (`creep_fate`), `waste` those no hero got (fate
-- `other`), then `waste` split by the view `lane_waste`'s `cause` (first match: tower, core_on, pulled, core_reach, sup_reach,
-- camp, no_reach); `nr_core_near` the no_reach deaths with a core logged within 1,500 (beyond reach), `untagged` waste from a build
-- without `tw` (there `tower` reads 0 and those deaths fall to later causes). Each team's log holds only the other team's
-- creeps: our pulled wave dying to neutrals is never in it.
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
den AS (
    SELECT f.game_id, f.team, count(*) AS deaths FROM creep_fate f
    WHERE f.game_id IN (SELECT game_id FROM gm) AND f.side = 'enemy' AND f.t < coalesce(:until, 600)
    GROUP BY f.game_id, f.team
),
w AS (
    SELECT game_id, team, count(*) AS waste,
        sum(cause = 'tower') AS tower, sum(cause = 'core_on') AS core_on, sum(cause = 'pulled') AS pulled, sum(cause = 'core_reach') AS core_reach,
        sum(cause = 'sup_reach') AS sup_reach, sum(cause = 'camp') AS camp, sum(cause = 'no_reach') AS no_reach,
        sum(cause = 'no_reach' AND core = 'near') AS nr_core_near, sum(tw IS NULL) AS untagged
    FROM lane_waste
    WHERE game_id IN (SELECT game_id FROM gm) AND t < coalesce(:until, 600)
    GROUP BY game_id, team
)
SELECT gm.file, den.game_id, den.team, den.deaths, coalesce(w.waste, 0) AS waste,
    round(CAST(coalesce(w.waste, 0) AS REAL) / den.deaths, 3) AS share,
    coalesce(w.tower, 0) AS tower, coalesce(w.core_on, 0) AS core_on, coalesce(w.pulled, 0) AS pulled, coalesce(w.core_reach, 0) AS core_reach,
    coalesce(w.sup_reach, 0) AS sup_reach, coalesce(w.camp, 0) AS camp, coalesce(w.no_reach, 0) AS no_reach,
    coalesce(w.nr_core_near, 0) AS nr_core_near, coalesce(w.untagged, 0) AS untagged
FROM den JOIN gm ON gm.game_id = den.game_id
LEFT JOIN w ON w.game_id = den.game_id AND w.team = den.team
ORDER BY den.game_id, den.team;
