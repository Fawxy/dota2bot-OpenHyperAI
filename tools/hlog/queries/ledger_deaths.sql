-- Every hero death before :until with one cause from what happened in the 10 s before it (the loss ledger, rework step 6; read
-- through ledger.js, which sets pos_lo 1, pos_hi 5 and until 720). The deaths are fragment core_death's; the cause rule is fragment
-- death_cause's (its header lists the causes, first match wins, and how attackers and allies are counted), which the timeline's
-- death rows share. Params: like (a path fragment), until, pos_lo, pos_hi.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: core_death
dc_in AS MATERIALIZED (SELECT game_id, pid, team, pos, t, x, y FROM cd),
dc_lineup AS MATERIALIZED (SELECT * FROM lineup),
-- include: death_cause
SELECT gm.file, f.game_id, f.team, f.pos, f.pid, f.t, f.attackers, f.allies, f.hp10, f.cause
FROM death_cause f JOIN gm ON gm.game_id = f.game_id
ORDER BY gm.file, f.t
