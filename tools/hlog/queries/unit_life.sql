-- unit_life (view) for the games a `game` id or a `like` log path fragment names (default: none, `like` defaults to no game): the same
-- rows as the view, whose store-wide read pairs every game. Params: game (a game_id), like (a path fragment or run label). Columns and
-- rules: view unit_life.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE game_id = :game OR (:like IS NOT NULL AND file LIKE :like)),
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
-- include: unit_life_rows
SELECT * FROM unit_life_rows ORDER BY game_id, t1, uid
