-- Lane creep and neutral deaths with their place in a window, for `hlog.js scene`: one row per unit (unit_life's lane rows, fragment unit_life_lane: a creep both
-- teams logged is one, so no row is dropped as another's duplicate), oldest first, every creep wherever it died. A creep alive at the end of the window is no row.
-- Params: game_id (games.game_id), lo and hi (seconds).
-- Row: t, team (the creep's own team; a neutral: the logging team), side (own for a lane creep, neutral), kind (melee, ranged, siege, neutral), x, y,
-- fate (own_lh a hero's last hit, own_deny, other, neutral), pid (the hero credited:
-- a text `none` for a neutral nobody credited), camp (neutral only).
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
WITH ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen WHERE game_id = :game_id),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone WHERE game_id = :game_id),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id = :game_id),
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id = :game_id),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id = :game_id),
-- include: unit_life_lane
SELECT t1 AS t, team, 'own' AS side, CASE WHEN type = 'flag' THEN 'melee' ELSE type END AS kind, x1 AS x, y1 AS y,
    CASE by_kind WHEN 'hero' THEN 'own_lh' WHEN 'deny' THEN 'own_deny' ELSE 'other' END AS fate,
    CASE WHEN by_kind IN ('hero', 'deny') THEN by_pid END AS pid, NULL AS camp
FROM ul_lall WHERE t1 >= :lo AND t1 <= :hi
UNION ALL
SELECT t, team, 'neutral', kind, x, y, 'neutral', "by", camp FROM ev_neutral_death
WHERE game_id = :game_id AND t >= :lo AND t <= :hi
ORDER BY t
