-- The replay's hits (unit_hit: a damage entry with a hero on one side) in a window, for `hlog.js scene`. Params: game_id, lo and hi (seconds).
SELECT t, ak, at, ap, an, tk, tt, tp, tn, dmg, inf FROM unit_hit WHERE game_id = :game_id AND t >= :lo AND t <= :hi ORDER BY t
