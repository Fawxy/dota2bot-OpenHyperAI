-- Lane creep and neutral deaths with their place in a window, for `hlog.js scene`: one row per unit (unit_life's lane rows, fragment unit_life_lane, and its neutral rows, fragment
-- unit_life_neutral: a creep or neutral both teams logged is one, so no row is dropped as another's duplicate), oldest first, every creep wherever it died. A creep alive at the end of the window is no row.
-- Params: game_id (games.game_id), lo and hi (seconds).
-- Row: t, team (the creep's own team; a neutral: 4), side (own for a lane creep, neutral), kind (melee, ranged, siege, neutral), x, y,
-- fate (own_lh a hero's last hit, own_deny, other, neutral), pid (the hero credited:
-- a text `none` for a neutral nobody credited), camp (neutral only).
WITH ul_gm AS (SELECT :game_id AS game_id),
-- include: unit_life_in
-- include: unit_life_lane
-- include: unit_life_neutral
SELECT t1 AS t, team, 'own' AS side, CASE WHEN type = 'flag' THEN 'melee' ELSE type END AS kind, x1 AS x, y1 AS y,
    CASE by_kind WHEN 'hero' THEN 'own_lh' WHEN 'deny' THEN 'own_deny' ELSE 'other' END AS fate,
    CASE WHEN by_kind IN ('hero', 'deny') THEN by_pid END AS pid, NULL AS camp
FROM ul_lall WHERE t1 >= :lo AND t1 <= :hi
UNION ALL
SELECT t1, 4, 'neutral', 'neutral', x1, y1, 'neutral', coalesce(by_pid, 'none'), camp
FROM ul_nlife WHERE t1 >= :lo AND t1 <= :hi
ORDER BY t
