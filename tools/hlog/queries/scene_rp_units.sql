-- The replay's units that were live at some time in a window, for `hlog.js scene` on a game `hlog.js replay` has read: rp_unit's columns
-- (replay.js has them). Params: game_id (games.game_id), lo and hi (seconds).
SELECT * FROM rp_unit WHERE game_id = :game_id AND t0 <= :hi AND (t1 IS NULL OR t1 >= :lo) ORDER BY t0, uid
