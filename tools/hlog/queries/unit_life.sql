-- unit_life (view) for the games a log names: the same rows as the view, whose store-wide read pairs every game. Params: like (a run
-- label or log path fragment, as the other queries) with game (the game's number in its log, default each log's last, as
-- `timeline --game`), or game_id (the store's id, a games row's game_id) alone. Reads only those games' events, by their
-- game_id index. Columns and rules: view unit_life.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id FROM games g
    WHERE g.game_id = :game_id
        OR (:like IS NOT NULL AND g.file LIKE :like AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)))
),
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen WHERE game_id IN (SELECT game_id FROM gm)),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone WHERE game_id IN (SELECT game_id FROM gm)),
-- include: unit_life_rows
SELECT * FROM unit_life_rows ORDER BY game_id, t1, uid
