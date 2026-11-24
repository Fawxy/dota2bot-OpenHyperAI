-- Fragment (`-- include: wave_fate`): every own lane creep's death by its wave and who took it (logs from team-bots c87cd648
-- on). Needs `gm(game_id)`, `tm(game_id, pid, pos)` and `camps` (fragment camp_spawns) before it. Ends with a comma.
--   wcr   each ev=wave_creep_death born before :to + 30 (default 525): owner, lane 1-3 (top, mid, bot), wave floor(born / 30).
--   wpair its sighting in the other team's log: ev=creep_death of the same kind within 1 s and 250 units, mutual nearest.
--   wfate one row a creep: game_id, team (its owner), lane, wave, fate (lh the other team's last hit; deny ours, from our `by`
--         or their `deny`; tower no hero and their tower on it; other the rest), pos (the last-hitter's), camp (died within
--         700 of a neutral camp's spawn point: no lane death came within 1,000 in the wave line's smoke, 0bfb851e, pulls off).
-- A line over half health is counted (a creep killed from there in one frame, or, rarely, a change of owner).
wcr AS MATERIALIZED (
    SELECT w.game_id, w.seq, w.t, w.team AS owner, w.kind, w.x, w.y, CAST(w."by" AS TEXT) AS who,
        CASE w.lane WHEN 'top' THEN 1 WHEN 'mid' THEN 2 WHEN 'bot' THEN 3 END AS lane, CAST(w.born / 30 AS INTEGER) AS wave
    FROM ev_wave_creep_death w
    WHERE w.game_id IN (SELECT game_id FROM gm) AND w.born IS NOT NULL AND w.born < coalesce(:to, 525) + 30
),
wsw AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, 5 - c.team AS owner, c.kind, c.x, c.y, CAST(c."by" AS TEXT) AS who, coalesce(c.tw, 0) AS tw
    FROM ev_creep_death c WHERE c.team IN (2, 3) AND c.game_id IN (SELECT game_id FROM wcr)
),
wpair AS MATERIALIZED (
    SELECT * FROM (
        SELECT w.game_id, w.seq AS wseq, s.who, s.tw,
            row_number() OVER (PARTITION BY w.game_id, w.seq ORDER BY (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y), abs(s.t - w.t), s.seq) AS rw,
            row_number() OVER (PARTITION BY s.game_id, s.seq ORDER BY (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y), abs(s.t - w.t), w.seq) AS rs
        FROM wcr w JOIN wsw s ON s.game_id = w.game_id AND s.owner = w.owner AND s.kind = w.kind
            AND s.t BETWEEN w.t - 1 AND w.t + 1 AND (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y) <= 62500
    ) WHERE rw = 1 AND rs = 1
),
wfate AS MATERIALIZED (
    SELECT w.game_id, w.owner AS team, w.lane, w.wave,
        CASE WHEN p.who IS NOT NULL AND p.who NOT IN ('none', 'deny') THEN 'lh'
             WHEN w.who <> 'none' OR p.who = 'deny' THEN 'deny'
             WHEN p.tw = 1 THEN 'tower' ELSE 'other' END AS fate,
        (SELECT b.pos FROM tm b WHERE b.game_id = w.game_id AND CAST(b.pid AS TEXT) = p.who) AS pos,
        EXISTS (SELECT 1 FROM camps k WHERE (k.x - w.x) * (k.x - w.x) + (k.y - w.y) * (k.y - w.y) <= 490000) AS camp
    FROM wcr w LEFT JOIN wpair p ON p.game_id = w.game_id AND p.wseq = w.seq
),
