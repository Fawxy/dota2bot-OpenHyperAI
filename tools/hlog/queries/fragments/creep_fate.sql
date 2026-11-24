-- Fragment (`-- include: creep_fate`): CTE `creep_fate(game_id, seq, t, team, side, kind, x, y, fate, pid, tw)`, who got each lane creep that died, both sides, one row per
-- creep death and side (what view creep_fate was; a view cannot take the games a query reads, and the lane chain it reads is slow unless it is given them). Needs `gm(game_id)`
-- before it, the games to read; reads unit_life's lane rows (fragment unit_life_lane: one row per unit, a game from team-bots bfc08402 from its unit_seen and unit_gone,
-- an older one from its death events). Ends with a comma.
--   side    `enemy`: the row of the team that could last-hit the creep (`team` that team; `seq` its creep_death line, which the join to ev_creep_death is on): fate own_lh (a hero of
--           `team` took it, `pid`), enemy_deny (a hero of the creep's owner denied it, `pid` the denier) or other (a tower, a creep, a spell the counters do not see, or no hero:
--           `tw` 1 when one of `team`'s towers hit it the frame before, NULL on builds before the field); only a creep the other team logged a death for.
--           `own`: the creep's owner's row (`team` the owner; `seq` its closing line), kept as a deny chance: the creep died within 1,500 of a living hero of its team
--           at half health or less (unit_life `near`, `hp1`): own_deny (an owner hero denied it, `pid`) or lost (anything else: an enemy last hit, tower or creep kill).
--   A creep is in both when an enemy hero's last hit or the like took it near an owner hero: count one side of one team per question. `t`, `x`, `y` are that side's last sighting.
ul_gm AS (SELECT game_id FROM gm),
-- include: unit_life_in
-- include: unit_life_lane
creep_fate AS MATERIALIZED (SELECT * FROM creep_fate_rows),
