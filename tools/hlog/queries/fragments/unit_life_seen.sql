-- Fragment (`-- include: unit_life_seen`): the unit_seen / unit_gone half every unit_life fragment starts from. Needs `ul_useen` and `ul_ugone` (fragment unit_life_in) before it.
-- CTEs `ul_new` (the games with unit_seen rows: read from those, any other from the old death events), `ul_s` (a unit's first sighting) and `ul_g` (its gone line). Ends with a comma.
-- A game with unit_seen rows (telemetry.ts trackCreepDeaths, ev=unit_seen / ev=unit_gone): a row per own lane creep, from its
-- owner's two lines, and one per neutral, the two teams' sightings merged. A cid is its team's own, so a unit is (team, cid).
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
ul_new AS MATERIALIZED (SELECT DISTINCT game_id FROM ul_useen),
ul_s AS NOT MATERIALIZED (SELECT game_id, seq, t, team, cid, kind, type, lane, camp, x, y FROM ul_useen),
ul_g AS NOT MATERIALIZED (
    SELECT game_id, seq, t, team, cid, x, y, CAST("by" AS TEXT) AS who, coalesce(hid, 0) AS hid, hp FROM ul_ugone
),
