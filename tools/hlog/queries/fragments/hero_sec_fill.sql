-- Fills the store's `hero_sec` table (store.js `fillHeroSec`; not a query): the rows of ep_sec for the games in the temp table
-- `hs_todo(game_id)`, with the attack target (ep_hit), the lane (ep_place) and who is near. Every column of the table that an
-- episode fragment also defines is read from it, so the rules have one definition. The whole game, whatever it is asked for.
-- near: distance to the nearest live enemy hero, whole units; en900, al900: live enemy and allied heroes (not itself) within 900.
WITH gm AS MATERIALIZED (SELECT game_id FROM hs_todo),
ep_win AS (SELECT -1e9 AS lo, 1e9 AS hi),
-- include: ep_attack
-- include: ep_visit
hs_near AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.sec,
        CAST(sqrt(min(CASE WHEN o.team <> s.team THEN (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) END)) AS INTEGER) AS near,
        coalesce(sum(o.team <> s.team AND (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) <= 900 * 900), 0) AS en900,
        coalesce(sum(o.team = s.team AND (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) <= 900 * 900), 0) AS al900
    FROM ep_sec s LEFT JOIN ep_sec o ON o.game_id = s.game_id AND o.sec = s.sec AND o.pid <> s.pid AND o.live
    GROUP BY s.game_id, s.pid, s.sec
)
INSERT INTO hero_sec (game_id, pid, team, pos, hero, sec, x, y, hp, mode, live, life, lane, hits, near, en900, al900)
SELECT s.game_id, s.pid, s.team, s.pos, w.hero, s.sec, s.x, s.y, s.hp, s.mode, s.live, s.life, p.lane, h.tpid, n.near, n.en900, n.al900
FROM ep_sec s
JOIN ep_who w ON w.game_id = s.game_id AND w.pid = s.pid
LEFT JOIN ep_place p ON p.game_id = s.game_id AND p.pid = s.pid AND p.sec = s.sec
LEFT JOIN ep_hit h ON h.game_id = s.game_id AND h.apid = s.pid AND h.sec = s.sec
JOIN hs_near n ON n.game_id = s.game_id AND n.pid = s.pid AND n.sec = s.sec
