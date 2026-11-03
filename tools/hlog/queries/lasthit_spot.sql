-- Where cores' missed last hits died against the core's lane spot (slice lane-positioning: is a miss the spot's or the picker's).
-- One row per core kind and band of the creep's distance from the spot, :from to :until (default 90-600), lineup cores pos 1-3.
-- Creeps and the miss classes are @lasthit_cores': enemy lane creeps that died within 1000 of the core; got = its own last hit;
-- swung = it began a swing (early or late); in_range = within attack range + 300 and not attacking; away = further.
-- The spot is the core's nearest ev=lane_pos sample with `sx`/`sy` from 2 s before the death to 0.5 s after (our spot only:
-- samples on OHA's spot (`spot=oha`, which can carry `sx`/`sy` too) are skipped; deaths with no such sample are dropped).
--   me          the core's kind: melee (attack range 200 or less) or ranged
--   band        the creep's distance from the spot less the core's attack range: in range (0 or less), +300, +600, beyond
--   ds, off     mean distance from the spot to the creep, and the core's own distance from its spot (`lane_pos` `d`)
--   hero..xp    the sample's `why` (the first limit the preferred point broke) over every row of the band
-- Params: like, from, until.
-- ensure: ev_creep_death(team, x, y, by, p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
-- ensure: ev_lane_pos(pid, d, why, sx, sy, spot)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
cores AS MATERIALIZED (SELECT l.game_id, l.team, l.pos, l.pid FROM lineup l JOIN gm ON gm.game_id = l.game_id WHERE l.pos BETWEEN 1 AND 3),
d AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, c.x, c.y, co.pid,
        CASE WHEN f.fate = 'enemy_deny' THEN 'deny' ELSE c."by" END AS killer,
        CASE co.pos WHEN 1 THEN c.p1d WHEN 2 THEN c.p2d ELSE c.p3d END AS pd,
        coalesce(CASE co.pos WHEN 1 THEN c.p1r WHEN 2 THEN c.p2r ELSE c.p3r END, 150) AS pr,
        CASE co.pos WHEN 1 THEN c.p1t WHEN 2 THEN c.p2t ELSE c.p3t END AS pt,
        CASE co.pos WHEN 1 THEN c.p1a WHEN 2 THEN c.p2a ELSE c.p3a END AS pa
    FROM ev_creep_death c JOIN gm ON gm.game_id = c.game_id
    JOIN cores co ON co.game_id = c.game_id AND co.team = c.team
    LEFT JOIN creep_fate f ON f.game_id = c.game_id AND f.seq = c.seq AND f.side = 'enemy'
    WHERE c.t >= coalesce(:from, 90) AND c.t < coalesce(:until, 600)
),
k AS MATERIALIZED (
    SELECT d.*,
        CASE WHEN CAST(killer AS TEXT) = CAST(pid AS TEXT) THEN 'got'
             WHEN typeof(pa) IN ('integer', 'real') AND pa >= 0 THEN 'swung'
             WHEN pt = 1 THEN 'swung'
             WHEN pd <= pr + 300 THEN 'in_range'
             ELSE 'away' END AS st
    FROM d WHERE pd IS NOT NULL AND pd <= 1000
),
sp AS (
    SELECT k.*, p.sx, p.sy, p.why, p.d AS off,
        row_number() OVER (PARTITION BY k.game_id, k.seq, k.pid ORDER BY abs(p.t - k.t), p.seq) AS rk
    FROM k JOIN ev_lane_pos p ON p.game_id = k.game_id AND p.pid = k.pid
        AND p.t BETWEEN k.t - 2 AND k.t + 0.5 AND p.sx IS NOT NULL AND p.spot IS NOT 'oha'
),
x AS (SELECT sp.*, sqrt((x - sx) * (x - sx) + (y - sy) * (y - sy)) AS ds FROM sp WHERE rk = 1)
SELECT CASE WHEN pr <= 200 THEN 'melee' ELSE 'ranged' END AS me,
    CASE WHEN ds - pr <= 0 THEN 'a:in range' WHEN ds - pr <= 300 THEN 'b:+300' WHEN ds - pr <= 600 THEN 'c:+600' ELSE 'd:beyond' END AS band,
    count(*) AS n, sum(st = 'got') AS got, sum(st = 'swung') AS swung, sum(st = 'in_range') AS in_range, sum(st = 'away') AS away,
    round(sum(st = 'got') * 1.0 / count(*), 2) AS got_rate, round(avg(ds)) AS ds, round(avg(off)) AS off,
    sum(why = 'hero') AS hero, sum(why = 'creep') AS creep, sum(why = 'pref') AS pref, sum(why = 'hp') AS hp,
    sum(why = 'tower') AS tower, sum(why = 'xp') AS xp
FROM x GROUP BY 1, 2 ORDER BY 1, 2
