-- Where lineup cores (pos 1-3) stood while idle in lane, :from to :until (default 90-600), per game and core (slice
-- lane-positioning, step 1 targets). Idle = laning mode with no attack target (lane_activity activity 'lane'), one snapshot a
-- second, less the seconds the laning body was walking to a last hit or deny (ev=lane_pos label lasthit/deny in that second or
-- the one before; lane_pos comes every 2 s): those belong to the last-hit picker, not the spot, and are counted apart.
--   lh_walk     idle snapshots spent walking to a last hit or deny;  lh_walk_hpl  HP-% points lost from them
--   idle        the other idle snapshots (the spot's)
--   ring        idle within 520 of the enemy team's lane front on the hero's lane (EC-053 creep acquisition around the enemy wave's lead)
--   ring_hpl    HP-% points lost from those snapshots to the next one (creeps, heroes and towers alike)
--   out_hpl     the same for idle snapshots outside that ring
--   tower       idle within 750 of an enemy tower (lane_spot TOWER_RING)
--   near        idle with a visible enemy hero within 800 (snapshot `ed`; step 0: idle HP loss was 1.6-3 a second there, 0.2 beyond 1,000)
--   near_hpl    HP-% points lost from those snapshots to the next;  hpl  all idle HP lost (ring_hpl + out_hpl)
--   per_min     ring seconds per idle minute
--   why_*       ev=lane_pos samples by the limit that decided our spot (absent on OHA's spot)
-- Params: like, from, until.
-- ensure: ev_front(team, topx, topy, midx, midy, botx, boty)
-- ensure: ev_lane_pos(pid, spot, why, label)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
fr AS MATERIALIZED (
    SELECT f.game_id, f.team, CAST(round(f.t) AS INTEGER) AS sec, max(f.topx) AS topx, max(f.topy) AS topy, max(f.midx) AS midx,
        max(f.midy) AS midy, max(f.botx) AS botx, max(f.boty) AS boty
    FROM ev_front f JOIN gm ON gm.game_id = f.game_id WHERE f.t <= coalesce(:until, 600) + 1
    GROUP BY f.game_id, f.team, CAST(round(f.t) AS INTEGER)
),
a AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.team, a.t, a.x, a.y, a.hp, a.activity, a.ed, s.ln,
        lead(a.hp) OVER (PARTITION BY a.game_id, a.pid ORDER BY a.t) AS nhp
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id JOIN ev_snap s ON s.game_id = a.game_id AND s.seq = a.seq
    WHERE a.pos <= 3 AND a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
),
-- Enemy tower positions: the table @core_deaths keeps equal to dynamic.js TOWERS.
tw (team, x, y) AS (VALUES
    (2, -3952, -6112), (2, -4640, -4144), (2, -6592, -3408), (2, -360, -6256), (2, 4860, -6379), (2, -3190, -2926),
    (2, -6501, -872), (2, -6336, 1856), (2, -5712, -4864), (2, -5392, -5192), (2, -1544, -1408),
    (3, 4944, 4776), (3, -128, 6016), (3, -5275, 6036), (3, 2496, 2112), (3, 524, 652), (3, 6400, 384), (3, 6336, 3032),
    (3, 3552, 5776), (3, 4272, 3759), (3, 5280, 4432), (3, 6269, -2240)),
lb0 AS MATERIALIZED (
    SELECT lp.game_id, lp.pid, CAST(round(lp.t) AS INTEGER) AS sec, max(lp.label IN ('lasthit', 'deny')) AS lh
    FROM ev_lane_pos lp JOIN gm ON gm.game_id = lp.game_id GROUP BY 1, 2, 3
),
-- Each sample covers its own second and the next.
lb AS MATERIALIZED (
    SELECT game_id, pid, sec, max(lh) AS lh FROM (SELECT game_id, pid, sec, lh FROM lb0 UNION ALL SELECT game_id, pid, sec + 1, lh FROM lb0)
    GROUP BY 1, 2, 3
),
i AS (
    SELECT a.*,
        coalesce(lb.lh, 0) AS lhw,
        (SELECT CASE a.ln WHEN 'top' THEN (fr.topx - a.x) * (fr.topx - a.x) + (fr.topy - a.y) * (fr.topy - a.y)
                          WHEN 'mid' THEN (fr.midx - a.x) * (fr.midx - a.x) + (fr.midy - a.y) * (fr.midy - a.y)
                          WHEN 'bot' THEN (fr.botx - a.x) * (fr.botx - a.x) + (fr.boty - a.y) * (fr.boty - a.y) END
            FROM fr WHERE fr.game_id = a.game_id AND fr.sec = CAST(round(a.t) AS INTEGER) AND fr.team <> a.team) <= 520 * 520 AS ring,
        EXISTS (SELECT 1 FROM tw WHERE tw.team <> a.team AND (tw.x - a.x) * (tw.x - a.x) + (tw.y - a.y) * (tw.y - a.y) <= 750 * 750) AS twr,
        CASE WHEN a.nhp IS NULL THEN 0 ELSE max(0, a.hp - a.nhp) END AS lost
    FROM a LEFT JOIN lb ON lb.game_id = a.game_id AND lb.pid = a.pid AND lb.sec = CAST(round(a.t) AS INTEGER) WHERE a.activity = 'lane'
),
p AS (
    SELECT lp.game_id, lp.pid, sum(lp.why = 'pref') AS why_pref, sum(lp.why = 'hero') AS why_hero, sum(lp.why = 'creep') AS why_creep, sum(lp.why = 'hp') AS why_hp,
        sum(lp.why = 'tower') AS why_tower, sum(lp.why = 'xp') AS why_xp
    FROM ev_lane_pos lp JOIN gm ON gm.game_id = lp.game_id
    WHERE lp.t >= coalesce(:from, 90) AND lp.t <= coalesce(:until, 600) AND lp.why IS NOT NULL
    GROUP BY lp.game_id, lp.pid
),
r AS (
    SELECT gm.file, i.team, l.pos, i.pid, sum(i.lhw) AS lh_walk, sum(CASE WHEN i.lhw THEN i.lost ELSE 0 END) AS lh_walk_hpl,
        sum(NOT i.lhw) AS idle, sum(CASE WHEN i.lhw THEN 0 ELSE coalesce(i.ring, 0) END) AS ring,
        sum(CASE WHEN i.ring AND NOT i.lhw THEN i.lost ELSE 0 END) AS ring_hpl, sum(CASE WHEN i.ring OR i.lhw THEN 0 ELSE i.lost END) AS out_hpl,
        sum(CASE WHEN i.lhw THEN 0 ELSE i.twr END) AS tower, sum(CASE WHEN i.lhw THEN 0 ELSE coalesce(i.ed < 800, 0) END) AS near,
        sum(CASE WHEN i.ed < 800 AND NOT i.lhw THEN i.lost ELSE 0 END) AS near_hpl,
        sum(CASE WHEN i.lhw THEN 0 ELSE i.lost END) AS hpl,
        round(60.0 * sum(CASE WHEN i.lhw THEN 0 ELSE coalesce(i.ring, 0) END) / max(1, sum(NOT i.lhw)), 1) AS per_min,
        p.why_pref, p.why_hero, p.why_creep, p.why_hp, p.why_tower, p.why_xp
    FROM i JOIN gm ON gm.game_id = i.game_id JOIN lineup l ON l.game_id = i.game_id AND l.pid = i.pid
    LEFT JOIN p ON p.game_id = i.game_id AND p.pid = i.pid
    GROUP BY i.game_id, i.pid
)
SELECT * FROM r ORDER BY file, team, pos
