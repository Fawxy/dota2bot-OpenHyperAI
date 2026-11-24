-- Fragment (`-- include: wave_fate`): every own lane creep's death by its wave and who took it (logs from team-bots c87cd648
-- on), read from unit_life's lane rows (fragment unit_life_lane, CTE ul_lall, never the replay's: the owner's line paired to the other team's sighting). Needs
-- `gm(game_id)`, `tm(game_id, pid, pos)` and `camps` (fragment camp_spawns) before it. Ends with a comma.
--   wfate one row a creep born before :to + 30 (default 525): game_id, team (its owner), lane 1-3 (top, mid, bot), wave
--         floor(born / 30), fate (lh the other team's last hit; deny ours, from our `by` or their `deny`; tower no hero and
--         their tower on it; other the rest: unit_life's by_kind hero, deny, tower, unknown), pos (the last-hitter's), camp
--         (died within 700 of a neutral camp's spawn point: no lane death came within 1,000 in the wave line's smoke,
--         0bfb851e, pulls off).
-- A line over half health is counted (a creep killed from there in one frame, or, rarely, a change of owner). A game with no wave
-- event and no unit_seen has no row (no unit has a wave). The fragment includes unit_life_in and unit_life_lane for the games `gm`
-- names, so the includer reads the own deny chances (CTE ul_odeath) from them too.
ul_gm AS (SELECT game_id FROM gm),
-- include: unit_life_in
-- include: unit_life_lane
wfate AS MATERIALIZED (
    SELECT u.game_id, u.team, CASE u.lane WHEN 'top' THEN 1 WHEN 'mid' THEN 2 WHEN 'bot' THEN 3 END AS lane, u.wave,
        CASE u.by_kind WHEN 'hero' THEN 'lh' WHEN 'deny' THEN 'deny' WHEN 'tower' THEN 'tower' ELSE 'other' END AS fate,
        (SELECT b.pos FROM tm b WHERE b.game_id = u.game_id AND u.by_kind = 'hero' AND CAST(b.pid AS TEXT) = CAST(u.by_pid AS TEXT)) AS pos,
        EXISTS (SELECT 1 FROM camps k WHERE (k.x - u.x1) * (k.x - u.x1) + (k.y - u.y1) * (k.y - u.y1) <= 490000) AS camp
    FROM ul_lall u
    WHERE u.kind = 'lane' AND u.t0 IS NOT NULL AND u.t1 IS NOT NULL AND u.t0 < coalesce(:to, 525) + 30
),
