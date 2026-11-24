-- The replay's unit positions (unit_pos, once a second) in a window, for `hlog.js scene`. Params: game_id, lo and hi (seconds).
SELECT uid, t, x, y FROM unit_pos WHERE game_id = :game_id AND t >= :lo AND t <= :hi ORDER BY uid, t
