-- Fragment (`-- include: unit_life_in`): the log events fragments unit_life_lane, unit_life_neutral and unit_life_rows read, each `AS NOT MATERIALIZED` and cut to the games of CTE
-- `ul_gm(game_id)`, which the includer defines first. The one place a reader of unit_life names the old death events (a game before team-bots bfc08402 is read from them) and the
-- unit_seen / unit_gone rows: `ul_wave` (ev_wave_creep_death), `ul_own` (ev_own_creep_death), `ul_enemy` (ev_creep_death), `ul_neu` (ev_neutral_death), `ul_useen`, `ul_ugone`.
-- A reader of lane creeps or neutrals includes this and the unit_life fragment it needs, and reads no death event of its own. Ends with a comma.
-- ensure: ev_wave_creep_death(team, kind, x, y, hp, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, hp, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, hp, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id IN (SELECT game_id FROM ul_gm)),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM ul_gm)),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM ul_gm)),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM ul_gm)),
ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen WHERE game_id IN (SELECT game_id FROM ul_gm)),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone WHERE game_id IN (SELECT game_id FROM ul_gm)),
