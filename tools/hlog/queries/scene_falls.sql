-- The towers and barracks that fell by a time, for `hlog.js scene`: every ev=building_fall of the game with t <= hi, oldest first.
-- Params: game_id (games.game_id), hi (seconds). `id` is the API's tower constant (top 1-3 = 0-2, mid 3-5, bot 6-8, base 9-10).
-- ensure: ev_building_fall(team, kind, id, tier)
SELECT t, team, kind, id, tier FROM ev_building_fall WHERE game_id = :game_id AND t <= :hi ORDER BY t, seq
