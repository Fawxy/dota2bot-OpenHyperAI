-- Lane fronts and heroes' places along their lanes at a clock (replaces front.js). Amounts are absolute: 0 = Radiant's ancient, 1 = Dire's.
-- Params: file (absolute log path, as in games.file), game (default 1), t (seconds). Each row is the latest ev=front per team
-- (kind 'front', who = team) or the latest ev=snap with a lane per hero (kind 'hero', who = pid) at or before t.
-- Order matches front.js: fronts by team, heroes by pid.
-- `+game_id` in the subqueries: a plain column compared with a subquery value cannot use the game_id index, a unary plus lets it.
-- ensure: ev_front(team, top, topx, topy, mid, midx, midy, bot, botx, boty)
-- ensure: ev_snap(pid, ln, s, ld, x, y)
WITH f AS (
    SELECT 'front' AS kind, team AS who, NULL AS hero, t, top, topx, topy, mid, midx, midy, bot, botx, boty,
        NULL AS ln, NULL AS s, NULL AS ld, NULL AS x, NULL AS y,
        row_number() OVER (PARTITION BY team ORDER BY seq DESC) AS rn
    FROM ev_front
    WHERE game_id = (SELECT +game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)) AND t <= :t
),
h AS (
    SELECT 'hero' AS kind, pid AS who, NULL AS hero, t, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ln, s, ld, x, y,
        row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn
    FROM ev_snap
    WHERE game_id = (SELECT +game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)) AND ln IS NOT NULL AND t <= :t
)
SELECT kind, who,
    (SELECT n.hero FROM hero_names n WHERE n.game_id = (SELECT +game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)) AND n.pid = u.who AND u.kind = 'hero') AS hero,
    t, top, topx, topy, mid, midx, midy, bot, botx, boty, ln, s, ld, x, y
FROM (SELECT * FROM f UNION ALL SELECT * FROM h) u
WHERE rn = 1
ORDER BY kind, who
