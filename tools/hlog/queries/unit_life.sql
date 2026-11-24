-- unit_life (view) for the games a log names: the same rows as the view, whose store-wide read pairs every game. Params: like (a run
-- label or log path fragment, as the other queries) with game (the game's number in its log, default each log's last, as
-- `timeline --game`), or game_id (the store's id, a games row's game_id) alone. Reads only those games' events, by their
-- game_id index. Columns and rules: view unit_life. A game `hlog.js replay` has read gives the replay's units (src replay).
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id FROM games g
    WHERE g.game_id = :game_id
        OR (:like IS NOT NULL AND g.file LIKE :like AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)))
),
ul_gm AS (SELECT game_id FROM gm),
-- include: unit_life_in
ul_rp AS NOT MATERIALIZED (SELECT * FROM rp_unit WHERE game_id IN (SELECT game_id FROM gm)),
-- include: unit_life_rows
SELECT * FROM unit_life_rows ORDER BY game_id, t1, uid
