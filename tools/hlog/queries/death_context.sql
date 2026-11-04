-- What a core did in the 30 s before each death before :until (default 600), one row per death of @core_deaths (same rule and
-- cause, fragment core_death). Lane positioning step 0 (docs/proposals/2026-11-03-lane-positioning.md): did the core die standing
-- in lane in reach of enemy heroes, creeps or a tower, or during actions? Counts are snapshots (about one per second) in the window:
--   secs       snapshots alive in the window
--   low        hp 25-40%;  retreat  in retreat mode;  swaps  mode changes between snapshots
--   idle       laning mode with no attack target (standing or walking in lane: the spot's time)
--   reach      in reach of an enemy hero: one within its own attack range + 100 at its snapshot in the same whole second (attack range 550
--              when its snapshot has none);  idle_reach  the same while idle
--   idle_creep idle within 520 of the enemy team's lane front on the core's lane (EC-053 creep acquisition, the enemy wave's lead)
--   idle_tower idle within 750 of an enemy tower (lane_spot TOWER_RING)
--   hit        snapshots hit by a hero in the last second;  hit_idle  the same while idle
--   en_last    enemy heroes within 1,200 at the last snapshot
-- Params: like, until; pos_lo, pos_hi the lineup positions (default 1-3; 4-5 reads the supports, slice support-spot).
-- ensure: ev_front(team, topx, topy, midx, midy, botx, boty)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: core_death
dd AS MATERIALIZED (SELECT game_id, pid, t, team, cause, x, y FROM cd),
w AS MATERIALIZED (
    SELECT cd.game_id, cd.pid, cd.t AS dt, cd.team, cd.cause, cd.x AS dx, cd.y AS dy, a.t, CAST(round(a.t) AS INTEGER) AS sec, a.x, a.y, a.hp, a.mode,
        a.activity, a.hit, s.ln, lag(a.mode) OVER (PARTITION BY cd.game_id, cd.pid, cd.t ORDER BY a.t) AS pmode
    FROM dd cd JOIN lane_activity a ON a.game_id = cd.game_id AND a.pid = cd.pid AND a.t > cd.t - 30 AND a.t <= cd.t
    JOIN ev_snap s ON s.game_id = a.game_id AND s.pid = a.pid AND s.t = a.t AND s.seq = a.seq
),
-- Enemy hero positions and the enemy lane fronts, by whole second (equality joins: the window is a few thousand snapshots).
es AS MATERIALIZED (
    SELECT s.game_id, l.team, CAST(round(s.t) AS INTEGER) AS sec, s.x, s.y, coalesce(s.ar, 550) AS ar
    FROM ev_snap s JOIN gm ON gm.game_id = s.game_id JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
    WHERE s.alive IS NOT 0 AND s.x IS NOT NULL AND s.t <= coalesce(:until, 600) + 1
),
fr AS MATERIALIZED (
    SELECT f.game_id, f.team, CAST(round(f.t) AS INTEGER) AS sec, max(f.topx) AS topx, max(f.topy) AS topy, max(f.midx) AS midx,
        max(f.midy) AS midy, max(f.botx) AS botx, max(f.boty) AS boty
    FROM ev_front f JOIN gm ON gm.game_id = f.game_id WHERE f.t <= coalesce(:until, 600) + 1
    GROUP BY f.game_id, f.team, CAST(round(f.t) AS INTEGER)
),
f AS (
    SELECT w.*,
        EXISTS (SELECT 1 FROM es WHERE es.game_id = w.game_id AND es.sec = w.sec AND es.team <> w.team
            AND (es.x - w.x) * (es.x - w.x) + (es.y - w.y) * (es.y - w.y) <= (es.ar + 100) * (es.ar + 100)) AS reach,
        (SELECT CASE w.ln WHEN 'top' THEN (fr.topx - w.x) * (fr.topx - w.x) + (fr.topy - w.y) * (fr.topy - w.y)
                          WHEN 'mid' THEN (fr.midx - w.x) * (fr.midx - w.x) + (fr.midy - w.y) * (fr.midy - w.y)
                          WHEN 'bot' THEN (fr.botx - w.x) * (fr.botx - w.x) + (fr.boty - w.y) * (fr.boty - w.y) END
            FROM fr WHERE fr.game_id = w.game_id AND fr.sec = w.sec AND fr.team <> w.team) AS front2,
        EXISTS (SELECT 1 FROM tw WHERE tw.team <> w.team AND (tw.x - w.x) * (tw.x - w.x) + (tw.y - w.y) * (tw.y - w.y) <= 750 * 750) AS twr
    FROM w
),
r AS (
    SELECT gm.file, f.team, f.pid, f.dt AS t, f.cause, count(*) AS secs,
        sum(f.hp >= 25 AND f.hp <= 40) AS low, sum(f.mode = 'retreat') AS retreat,
        sum(f.pmode IS NOT NULL AND f.mode IS NOT f.pmode) AS swaps,
        sum(f.activity = 'lane') AS idle, sum(f.reach) AS reach, sum(f.activity = 'lane' AND f.reach) AS idle_reach,
        sum(f.activity = 'lane' AND f.front2 <= 520 * 520) AS idle_creep, sum(f.activity = 'lane' AND f.twr) AS idle_tower,
        sum(coalesce(f.hit, 0) > 0) AS hit, sum(coalesce(f.hit, 0) > 0 AND f.activity = 'lane') AS hit_idle,
        (SELECT count(*) FROM es WHERE es.game_id = f.game_id AND es.sec = CAST(round(f.dt) AS INTEGER) AND es.team <> f.team
            AND (es.x - f.dx) * (es.x - f.dx) + (es.y - f.dy) * (es.y - f.dy) <= 1200 * 1200) AS en_last
    FROM f JOIN gm ON gm.game_id = f.game_id
    GROUP BY f.game_id, f.pid, f.dt
)
SELECT * FROM r ORDER BY file, t
