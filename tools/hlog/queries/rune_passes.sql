-- Rune passes (family rune trips, master docs/proposals/2026-11-24-next-three-families.md s7): one row per pass of a hero by its
-- own jungle's live bounty while out of its lane, and whether that hero took it. The group's line is the share of passes taken.
-- Found from what happened (hero_sec places, ev=rune_pickup), never from our own read, so it runs on both arms and on stock.
--   spawn   an own-jungle bounty: from 4:00 every 4:00 before :until, rune 2 (Dire's jungle, -997 4431) for Dire, rune 3
--           (Radiant's, 595 -4660) for Radiant (spots: the pickups' x y in every banked game; runes 4 and 5 log none).
--   live    from the spawn to the first pickup on its spot by either team, else to the next spawn (an untaken bounty is assumed
--           to lie until then, `judgement`; that it is there is not logged).
--   pass    a run of whole live seconds (hero_sec) of a hero of the owning side, inside the live window, within :r (default
--           1,800: the base walk's nearest point is about 1,300 to 1,750, `judgement`) of the spot, in none of its own lane's
--           seconds (lane <> its own lane as GetAssignedLane gives it: pos 2 mid; Radiant pos 1 and 5 bot, 3 and 4 top; Dire the
--           other way). A run broken by a second in its own lane, out of range or dead is two passes.
--   taken   1 when this hero's own ev=rune_pickup on the spot falls from t0 to t1 + 2 (the live window ends at the pickup).
--   came    hero_sec lane 15 s before t0 (base: the walk back from base; other: the jungle or river; a lane name: it left that
--           lane), null when not live then.
--   det     2 x dmin / 300, a rough detour in seconds to step from the closest point to the rune and back at 300 speed
--           (`judgement`: the hero's speed and the path are not read; the proposal's budget is about 12 s).
-- Columns: file, game, team, pid, pos, hero, sp (spawn second), rune, t0, t1, secs (t1 - t0 + 1), dmin (closest, rounded), tmin
-- (its first second), det, came, taken, gone (the rune's end of live: pickup second, or sp + 240 when untaken), by (pid that took
-- it, null untaken), byteam.
-- Params: like (a path fragment or run label; required), until (spawns before it, default 600), r (pass radius, default 1800).
-- ensure: ev_rune_pickup(pid, team, rune, kind)
WITH
gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '') AND bots > 0),
spot(rune, team, sx, sy) AS (VALUES (2, 3, -997.0, 4431.0), (3, 2, 595.0, -4660.0)),
sp AS MATERIALIZED (
    SELECT gm.game_id, s.rune, s.team, s.sx, s.sy, 240 * n.k AS sp
    FROM gm, spot s, (SELECT 1 AS k UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n
    WHERE 240 * n.k < coalesce(:until, 600)
),
lw AS MATERIALIZED (
    SELECT s.*, p.t AS pt, p.pid AS by, p.team AS byteam, coalesce(p.t, s.sp + 240) AS gone
    FROM sp s LEFT JOIN ev_rune_pickup p ON p.rowid = (
        SELECT q.rowid FROM ev_rune_pickup q WHERE q.game_id = s.game_id AND q.rune = s.rune AND q.t >= s.sp AND q.t < s.sp + 240
        ORDER BY q.t LIMIT 1)
),
near AS MATERIALIZED (
    SELECT w.game_id, w.rune, w.sp, w.gone, w.pt, w.by, w.byteam, h.pid, h.team, h.pos, h.hero, h.sec,
        sqrt((h.x - w.sx) * (h.x - w.sx) + (h.y - w.sy) * (h.y - w.sy)) AS d
    FROM lw w JOIN hero_sec h ON h.game_id = w.game_id AND h.team = w.team AND h.sec >= w.sp AND h.sec <= w.gone
    WHERE h.live
        AND (h.x - w.sx) * (h.x - w.sx) + (h.y - w.sy) * (h.y - w.sy) <= coalesce(:r, 1800) * coalesce(:r, 1800)
        AND coalesce(h.lane, '') <> CASE WHEN h.pos = 2 THEN 'mid'
             WHEN h.pos IN (1, 5) THEN CASE h.team WHEN 2 THEN 'bot' ELSE 'top' END
             ELSE CASE h.team WHEN 2 THEN 'top' ELSE 'bot' END END
),
isl AS (SELECT n.*, n.sec - row_number() OVER (PARTITION BY n.game_id, n.rune, n.sp, n.pid ORDER BY n.sec) AS grp FROM near n),
pass AS MATERIALIZED (
    SELECT game_id, rune, sp, gone, pt, by, byteam, pid, team, pos, hero, min(sec) AS t0, max(sec) AS t1, min(d) AS dmin
    FROM isl GROUP BY game_id, rune, sp, pid, grp
)
SELECT gm.file, gm.game, p.team, p.pid, p.pos, p.hero, p.sp, p.rune, p.t0, p.t1, p.t1 - p.t0 + 1 AS secs,
    round(p.dmin) AS dmin,
    (SELECT min(i.sec) FROM isl i WHERE i.game_id = p.game_id AND i.rune = p.rune AND i.sp = p.sp AND i.pid = p.pid
        AND i.sec BETWEEN p.t0 AND p.t1 AND i.d = p.dmin) AS tmin,
    round(2 * p.dmin / 300.0, 1) AS det,
    (SELECT h.lane FROM hero_sec h WHERE h.game_id = p.game_id AND h.pid = p.pid AND h.sec = p.t0 - 15 AND h.live) AS came,
    CASE WHEN p.by = p.pid AND p.byteam = p.team AND p.pt >= p.t0 AND p.pt <= p.t1 + 2 THEN 1 ELSE 0 END AS taken,
    round(p.gone, 1) AS gone, p.by, p.byteam
FROM pass p JOIN gm USING (game_id)
ORDER BY gm.file, gm.game, p.sp, p.rune, p.t0, p.pid
