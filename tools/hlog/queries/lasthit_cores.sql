-- Where cores lose last hits (WO-025; replaces the per-core half of lasthit_cause.js). One row per core (lineup position 1-3 of
-- each team) with the enemy lane creeps that died near it (within 1000 units, from ev=creep_death), who got them, and what the
-- core was doing when it did not. Params: file (absolute log path, as in games.file), game (default 1), until (s, default 600).
-- `lane` is the core's modal lane over 1:00 to `until` (snaps while alive, base and other ignored); a death is in the lane when
-- its place is nearest that lane's polyline (within 1100 units; base = within 1800 of an ancient or 1200 of a fountain).
-- Killer: core_lh (the core's own), enemy_deny, creep_or_tower (`none` or unset), else ally_lh. When the core did not get it,
-- late = its swing began under 0.6 s before the death (or a target was held), early = longer, idle_in_range = within attack range
-- + 300 and not attacking, away = further. lh = the core's last-hit counter at `until`; attributed = deaths credited to it.
-- Constants in this SQL (no other copy to keep equal except these): near 1000, late/early 0.6 s, reach 300, default attack range 150,
-- lane radius 1100, base radii 1800/1200, ancient and fountain positions, from dynamic.js `C`, `ANCIENT`, `FOUNTAIN` (test/lasthit_cause.test.js
-- pins the boundaries); `C` in lasthit_cause.js is printed by --json and must match.
-- `+game_id` in gm: a plain column compared with a subquery value cannot use the game_id index, a unary plus on the value lets it.
-- ensure: ev_creep_death(team, x, y, by, p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
-- ensure: ev_snap(pid, x, y, alive, lh)
-- ensure: ev_bot(pid, team, pos)
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
cores AS (
    SELECT l.team, l.pos, l.pid
    FROM lineup l
    WHERE l.game_id = (SELECT game_id FROM gm) AND l.pos BETWEEN 1 AND 3
      AND EXISTS (SELECT 1 FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL)
),
deaths AS (
    SELECT seq, team, x, y, "by" AS killer,
        p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a
    FROM ev_creep_death
    WHERE game_id = (SELECT game_id FROM gm) AND t < coalesce(:until, 600)
),
pts AS (
    SELECT 'snap' AS kind, s.pid AS k, s.seq, s.t, s.x, s.y
    FROM ev_snap s
    WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid IN (SELECT pid FROM cores)
      AND s.x IS NOT NULL AND s.t >= 60 AND s.t < coalesce(:until, 600) AND s.alive IS NOT 0
    UNION ALL
    SELECT 'death', seq, seq, NULL, x, y FROM deaths
),
lab AS (
    SELECT p.kind, p.k, p.seq, p.t,
        CASE
            WHEN sqrt((p.x + 5920) * (p.x + 5920) + (p.y + 5352) * (p.y + 5352)) < 1800
              OR sqrt((p.x - 5528) * (p.x - 5528) + (p.y - 5000) * (p.y - 5000)) < 1800
              OR sqrt((p.x + 6850) * (p.x + 6850) + (p.y + 6461) * (p.y + 6461)) < 1200
              OR sqrt((p.x - 7020) * (p.x - 7020) + (p.y - 6345) * (p.y - 6345)) < 1200 THEN 'base'
            ELSE coalesce((
                SELECT q.lane FROM (
                    SELECT g.lane, g.seg,
                        sqrt((p.x - (g.x1 + g.f * g.dx)) * (p.x - (g.x1 + g.f * g.dx)) + (p.y - (g.y1 + g.f * g.dy)) * (p.y - (g.y1 + g.f * g.dy))) AS d
                    FROM (
                        SELECT s.*, max(0.0, min(1.0, ((p.x - s.x1) * s.dx + (p.y - s.y1) * s.dy) / s.l2)) AS f FROM lane_segments s
                    ) g
                ) q
                WHERE q.d < 1100 ORDER BY q.d, q.seg LIMIT 1), 'other')
        END AS lane
    FROM pts p
),
home AS (
    SELECT k AS pid, lane, row_number() OVER (PARTITION BY k ORDER BY count(*) DESC, min(t), min(seq)) AS rk
    FROM lab WHERE kind = 'snap' AND lane NOT IN ('base', 'other')
    GROUP BY k, lane
),
cd AS (
    SELECT c.pid, c.pos, h.lane AS home, lab.lane AS dlane, d.killer,
        CASE c.pos WHEN 1 THEN d.p1d WHEN 2 THEN d.p2d ELSE d.p3d END AS pd,
        CASE c.pos WHEN 1 THEN d.p1r WHEN 2 THEN d.p2r ELSE d.p3r END AS pr,
        CASE c.pos WHEN 1 THEN d.p1t WHEN 2 THEN d.p2t ELSE d.p3t END AS pt,
        CASE c.pos WHEN 1 THEN d.p1a WHEN 2 THEN d.p2a ELSE d.p3a END AS pa
    FROM cores c
    JOIN deaths d ON d.team = c.team
    JOIN lab ON lab.kind = 'death' AND lab.k = d.seq
    LEFT JOIN home h ON h.pid = c.pid AND h.rk = 1
),
cdk AS (
    SELECT cd.*,
        CASE WHEN CAST(cd.killer AS TEXT) = CAST(cd.pid AS TEXT) THEN 'core_lh'
             WHEN cd.killer = 'deny' THEN 'enemy_deny'
             WHEN cd.killer IS NULL OR cd.killer = 'none' THEN 'creep_or_tower'
             ELSE 'ally_lh' END AS kk,
        CASE WHEN typeof(cd.pa) IN ('integer', 'real') AND cd.pa >= 0 THEN CASE WHEN cd.pa >= 0.6 THEN 'early' ELSE 'late' END
             WHEN cd.pt = 1 THEN 'late'
             WHEN cd.pd <= coalesce(cd.pr, 150) + 300 THEN 'idle_in_range'
             ELSE 'away' END AS st,
        (cd.pd IS NOT NULL AND cd.pd <= 1000) AS near,
        (cd.home IS NOT NULL AND cd.dlane = cd.home) AS in_lane
    FROM cd
)
SELECT (SELECT file FROM games WHERE game_id = (SELECT game_id FROM gm)) AS file, coalesce(:game, 1) AS game, c.team, c.pos, c.pid,
    (SELECT n.hero FROM hero_names n WHERE n.game_id = (SELECT game_id FROM gm) AND n.pid = c.pid) AS hero,
    (SELECT h.lane FROM home h WHERE h.pid = c.pid AND h.rk = 1) AS lane,
    coalesce(sum(k.near), 0) AS near,
    coalesce(sum(k.in_lane), 0) AS lane_deaths,
    coalesce(sum(k.in_lane AND NOT k.near), 0) AS absent,
    coalesce(sum(k.near AND k.kk = 'core_lh'), 0) AS core_lh,
    coalesce(sum(k.near AND k.kk = 'ally_lh'), 0) AS ally_lh,
    coalesce(sum(k.near AND k.kk = 'enemy_deny'), 0) AS enemy_deny,
    coalesce(sum(k.near AND k.kk = 'creep_or_tower'), 0) AS creep_or_tower,
    coalesce(sum(k.near AND k.kk <> 'core_lh' AND k.st = 'late'), 0) AS late,
    coalesce(sum(k.near AND k.kk <> 'core_lh' AND k.st = 'early'), 0) AS early,
    coalesce(sum(k.near AND k.kk <> 'core_lh' AND k.st = 'idle_in_range'), 0) AS idle_in_range,
    coalesce(sum(k.near AND k.kk <> 'core_lh' AND k.st = 'away'), 0) AS away,
    coalesce((SELECT s.lh FROM ev_snap s
              WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = c.pid AND s.x IS NOT NULL AND s.lh IS NOT NULL AND s.t <= coalesce(:until, 600)
              ORDER BY s.t DESC, s.seq DESC LIMIT 1), 0) AS lh,
    (SELECT count(*) FROM deaths d WHERE CAST(d.killer AS TEXT) = CAST(c.pid AS TEXT)) AS attributed
FROM cores c
LEFT JOIN cdk k ON k.pid = c.pid
GROUP BY c.pid, c.team, c.pos
ORDER BY c.team, c.pos
