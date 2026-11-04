-- Lane-wide waste by place and cause (slice support-lane): one row per game, logging team and `place` (view `lane_waste`: tower,
-- open, untagged), enemy lane creep deaths before :until (default 600) in games whose file matches :like. `deaths` the logged
-- enemy-side deaths (`creep_fate`) in that place (an enemy deny under our tower counts in tower), `waste` those no hero got
-- (fate `other`), `share` = waste / deaths, then the waste split by `cause` (first match: core_on, pulled, core_reach,
-- sup_reach, camp, no_reach); `nr_core_near` the no_reach deaths with a core logged within 1,500 (beyond reach). A build without
-- `tw` has only `untagged` rows, so its tower creeps are never read as open-lane ones; sum the rows of a team-game for its
-- totals. A team's pulled wave is only in the other team's log, where it reads `pulled`. The pre-hit's tower measure (reach
-- range + 100, `tower_excess`) is @creep_tower's, not this one's.
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
den AS (
    SELECT f.game_id, f.team, CASE WHEN c.tw = 1 THEN 'tower' WHEN c.tw = 0 THEN 'open' ELSE 'untagged' END AS place,
        count(*) AS deaths
    FROM creep_fate f JOIN ev_creep_death c ON c.game_id = f.game_id AND c.seq = f.seq
    WHERE f.game_id IN (SELECT game_id FROM gm) AND f.side = 'enemy' AND f.t < coalesce(:until, 600)
    GROUP BY 1, 2, 3
),
w AS (
    SELECT game_id, team, place, count(*) AS waste,
        sum(cause = 'core_on') AS core_on, sum(cause = 'pulled') AS pulled, sum(cause = 'core_reach') AS core_reach,
        sum(cause = 'sup_reach') AS sup_reach, sum(cause = 'camp') AS camp, sum(cause = 'no_reach') AS no_reach,
        sum(cause = 'no_reach' AND core = 'near') AS nr_core_near
    FROM lane_waste
    WHERE game_id IN (SELECT game_id FROM gm) AND t < coalesce(:until, 600)
    GROUP BY 1, 2, 3
)
SELECT gm.file, den.game_id, den.team, den.place, den.deaths, coalesce(w.waste, 0) AS waste,
    round(CAST(coalesce(w.waste, 0) AS REAL) / den.deaths, 3) AS share,
    coalesce(w.core_on, 0) AS core_on, coalesce(w.pulled, 0) AS pulled, coalesce(w.core_reach, 0) AS core_reach,
    coalesce(w.sup_reach, 0) AS sup_reach, coalesce(w.camp, 0) AS camp, coalesce(w.no_reach, 0) AS no_reach,
    coalesce(w.nr_core_near, 0) AS nr_core_near
FROM den JOIN gm ON gm.game_id = den.game_id
LEFT JOIN w ON w.game_id = den.game_id AND w.team = den.team AND w.place = den.place
ORDER BY den.game_id, den.team, CASE den.place WHEN 'tower' THEN 1 WHEN 'open' THEN 2 ELSE 3 END;
