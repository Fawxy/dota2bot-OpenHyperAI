-- The place of each logged lane creep death (fragment lane_label: top, mid, bot, base or other), keyed as view creep_fate's
-- rows are: (game_id, seq) of its ev=creep_death, ev=own_creep_death, ev=wave_creep_death or ev=unit_gone line (the owner's last sighting is where the unit died). Read it for the games a query needs (the
-- timeline's creep rows with no hero take their lane from it): store-wide it labels every creep death of every game.
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
WITH pts AS (
    SELECT game_id AS kind, seq AS k, seq, t, x, y FROM ev_creep_death
    UNION ALL
    SELECT game_id, seq, seq, t, x, y FROM ev_own_creep_death
    UNION ALL
    SELECT game_id, seq, seq, t, x, y FROM ev_unit_gone
    UNION ALL
    SELECT game_id, seq, seq, t, x, y FROM ev_wave_creep_death
),
-- include: lane_label
SELECT kind AS game_id, seq, lane FROM lab
