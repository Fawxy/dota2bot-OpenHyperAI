-- Rune pickup tries (slice rune-spawn, RunePickup): one row per rune id and result of `ev=rune_try`.
--   n          lines; act0/act the most common action types at the first order and at the end
--   held_after gave_up lines whose hero is still within 150 of where it stood 5-7 s later (from `ev=snap`): the give-up's target
-- Params: like.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
r AS (SELECT t.* FROM ev_rune_try t JOIN gm ON gm.game_id = t.game_id),
g AS (
    SELECT r.game_id, r.pid, r.t,
        (SELECT x FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t BETWEEN r.t - 1.5 AND r.t ORDER BY s.t DESC LIMIT 1) AS x0,
        (SELECT y FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t BETWEEN r.t - 1.5 AND r.t ORDER BY s.t DESC LIMIT 1) AS y0,
        (SELECT x FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t BETWEEN r.t + 5 AND r.t + 7 ORDER BY s.t LIMIT 1) AS x1,
        (SELECT y FROM ev_snap s WHERE s.game_id = r.game_id AND s.pid = r.pid AND s.t BETWEEN r.t + 5 AND r.t + 7 ORDER BY s.t LIMIT 1) AS y1
    FROM r WHERE r.res = 'gave_up'
)
SELECT r.rune, r.res, count(*) AS n,
    (SELECT act0 FROM r r2 WHERE r2.rune = r.rune AND r2.res = r.res GROUP BY act0 ORDER BY count(*) DESC LIMIT 1) AS act0,
    (SELECT act FROM r r2 WHERE r2.rune = r.rune AND r2.res = r.res GROUP BY act ORDER BY count(*) DESC LIMIT 1) AS act,
    CASE WHEN r.res = 'gave_up' THEN (SELECT count(*) FROM g JOIN r r3 ON r3.game_id = g.game_id AND r3.pid = g.pid AND r3.t = g.t
        WHERE r3.rune = r.rune AND g.x1 IS NOT NULL AND (g.x1 - g.x0) * (g.x1 - g.x0) + (g.y1 - g.y0) * (g.y1 - g.y0) <= 22500) END AS held_after
FROM r
GROUP BY r.rune, r.res
ORDER BY r.rune, r.res;
