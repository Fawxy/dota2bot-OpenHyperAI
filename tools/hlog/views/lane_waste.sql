-- Lane-wide waste by place and cause (slice support-lane, coverage "lane-wide waste"): one row per enemy lane creep death no hero got
-- (`creep_fate` side enemy, fate `other`), from either team's log, with who of the logging team was near it and why no one took it.
-- core_*: from ev=creep_death's p<N> fields (own cores pos 1-3 within 1,500): `core_d` the nearest one's distance; `core` = on
--   (a core was attacking this creep: p<N>t = 1 or p<N>a set), reach (a core within its attack range + 300, not on it), near
--   (logged within 1,500, beyond reach), none.
-- sup_*: the logging team's lineup pos 4-5, from each one's last alive ev=snap in the 1.5 s up to the death (snaps are 1 s apart):
--   `sup_d` the nearest one's distance, `sup_reach` 1 when one is within its `ar` (default 150) + 300.
-- pulled: the other team pulled this wave: an `ok` ev=pull_job by a hero not of the logging team, its camp's spawn within 800 of
--   the death, the death 0-30 s after the planned hit second (`slot`; 30 s, one wave, is `judgement`).
-- camp_d: distance to the nearest neutral camp's spawn point (fragment camp_spawns), and
--   `lane` the death's lane (fragment lane_label).
-- place: tower (tw = 1: one of our towers hit it the frame before; a creep our creeps finish under the tower reads the same, so
--   this is "under our tower", not "killed by it"), open (tw = 0), untagged (no tw: a build before the lasthit-refine-logs slice).
-- cause, first match, within every place: core_on (a core swung and lost the race), pulled (the other team's pull: their pull's
--   purpose, not our miss, unless a core swung), core_reach (a core in reach and not on it: Core in lane), sup_reach (a support
--   in reach and no one on it: Support in lane, its claims), camp (within 600 of a camp's spawn with no pull logged: neutrals,
--   or a pull from an older build; Camps in the laning stage), no_reach (no hero of ours in reach: Lane positioning).
-- Reach is range + 300, as @lasthit_cores' idle_in_range. @creep_tower's reach (range + 100) is the pre-hit's own window and
--   stays in that query: a tower death `core_reach` here is not its `tower_reach`. Camp radii are `judgement`: pull camps 2, 4, 15 and 18 have their
--   spawn inside the lane rule's 1,100, so `camp` takes no lane condition and stays at 600 (box half-sides are 300-600); most
--   `camp` rows are lane deaths beside those camps (scdchk1: 17 of 20), not neutrals.
-- ensure: ev_creep_death(team, kind, x, y, by, tw, p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
-- ensure: ev_snap(pid, x, y, alive, ar)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_pull_job(pid, camp, slot, res)
WITH
-- include: camp_spawns
d AS (
    SELECT c.game_id, c.seq, c.t, c.team, c.kind, c.x, c.y, c.tw,
        min(coalesce(c.p1d, 1e9), coalesce(c.p2d, 1e9), coalesce(c.p3d, 1e9)) AS core_d,
        (c.p1t = 1 OR typeof(c.p1a) IN ('integer', 'real') OR c.p2t = 1 OR typeof(c.p2a) IN ('integer', 'real')
            OR c.p3t = 1 OR typeof(c.p3a) IN ('integer', 'real')) AS on_it,
        (c.p1d <= coalesce(c.p1r, 150) + 300 OR c.p2d <= coalesce(c.p2r, 150) + 300 OR c.p3d <= coalesce(c.p3r, 150) + 300) AS in_reach
    FROM ev_creep_death c
    JOIN creep_fate f ON f.game_id = c.game_id AND f.seq = c.seq AND f.side = 'enemy' AND f.fate = 'other'
),
sup AS (
    SELECT d.game_id, d.seq,
        (SELECT s.x FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = l.pid AND s.t > d.t - 1.5 AND s.t <= d.t
            AND s.x IS NOT NULL AND s.alive IS NOT 0 ORDER BY s.t DESC LIMIT 1) AS sx,
        (SELECT s.y FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = l.pid AND s.t > d.t - 1.5 AND s.t <= d.t
            AND s.x IS NOT NULL AND s.alive IS NOT 0 ORDER BY s.t DESC LIMIT 1) AS sy,
        (SELECT s.ar FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = l.pid AND s.t > d.t - 1.5 AND s.t <= d.t
            AND s.x IS NOT NULL AND s.alive IS NOT 0 ORDER BY s.t DESC LIMIT 1) AS sar,
        d.x, d.y
    FROM d JOIN lineup l ON l.game_id = d.game_id AND l.team = d.team AND l.pos IN (4, 5)
),
sd AS (
    SELECT game_id, seq, min(sqrt((sx - x) * (sx - x) + (sy - y) * (sy - y))) AS sup_d,
        max(sqrt((sx - x) * (sx - x) + (sy - y) * (sy - y)) <= coalesce(sar, 150) + 300) AS sup_reach
    FROM sup WHERE sx IS NOT NULL GROUP BY game_id, seq
),
pts AS (SELECT 'death' AS kind, game_id AS k, seq, t, x, y FROM d),
-- include: lane_label
cd AS (
    SELECT d.game_id, d.seq, (SELECT min(sqrt((k.x - d.x) * (k.x - d.x) + (k.y - d.y) * (k.y - d.y))) FROM camps k) AS camp_d,
        EXISTS (SELECT 1 FROM ev_pull_job p JOIN camps k ON k.idx = p.camp
                WHERE p.game_id = d.game_id AND p.res = 'ok' AND d.t BETWEEN p.slot AND p.slot + 30
                  AND NOT EXISTS (SELECT 1 FROM ev_bot b WHERE b.game_id = p.game_id AND b.pid = p.pid AND b.team = d.team)
                  AND (k.x - d.x) * (k.x - d.x) + (k.y - d.y) * (k.y - d.y) <= 640000) AS pulled
    FROM d
)
SELECT d.game_id, d.seq, d.t, d.team, d.kind, d.x, d.y, d.tw, lab.lane,
    CASE WHEN d.core_d < 1e9 THEN round(d.core_d) END AS core_d,
    CASE WHEN d.on_it THEN 'on' WHEN d.in_reach THEN 'reach' WHEN d.core_d < 1e9 THEN 'near' ELSE 'none' END AS core,
    round(sd.sup_d) AS sup_d, coalesce(sd.sup_reach, 0) AS sup_reach, round(cd.camp_d) AS camp_d, cd.pulled,
    CASE WHEN d.tw = 1 THEN 'tower' WHEN d.tw = 0 THEN 'open' ELSE 'untagged' END AS place,
    CASE WHEN d.on_it THEN 'core_on'
         WHEN cd.pulled THEN 'pulled'
         WHEN d.in_reach THEN 'core_reach'
         WHEN sd.sup_reach THEN 'sup_reach'
         WHEN cd.camp_d <= 600 THEN 'camp'
         ELSE 'no_reach' END AS cause
FROM d
JOIN lab ON lab.k = d.game_id AND lab.seq = d.seq
JOIN cd ON cd.game_id = d.game_id AND cd.seq = d.seq
LEFT JOIN sd ON sd.game_id = d.game_id AND sd.seq = d.seq
