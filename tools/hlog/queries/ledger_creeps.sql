-- Every enemy lane creep a team could have taken before :at, with its fate for that team and, when the team did not get it, one
-- cause read from the lane's core (the loss ledger, rework step 6; read through ledger.js). The pool is the creeps the team saw
-- die (ev=creep_death: within 1,500 of a living hero of the team; `src` seen) and the other team's own creeps it saw die that the
-- team did not (ev=own_creep_death with no creep_death of this team within 1 s and 250 units of the same kind; `src` unseen).
-- Creeps neither team's heroes were near are in no log. The lane is the creep's place (fragment lane_label); the lane's core is
-- the team's pos 1-3 whose modal lane over 1:00 to :at is that lane (snapshot `ln` within 1,100 of its path). First match wins:
--   taken             a hero of the team got the last hit (`by` is its pid)
--   denied            an enemy hero denied it (view creep_fate, or the owner's own_creep_death `by`)
--   off_lane          it died in a base or outside every lane, or in a lane no core of the team holds
--   core_dead         the lane's core logged no living snapshot in the 2.5 s before
--   away_base         the core was alive, over 1,500 from it and not in its lane: in a base (fountain, healing, the walk out)
--   away_lane         ... in another lane
--   away_jungle       ... in no lane and no base (jungle, river, camps, runes)
--   far_in_lane       in its lane but over 1,500 from it (walking back up the lane, or the creep died far ahead)
--   swing_lost        the core was attacking it, or its last attack was on it
--   held_back_hero    the core stood in its lane beyond attack range + 300 with an enemy hero within 800 or a hero's hit in the last 3 s
--   held_back_low_hp  beyond that reach, under half HP
--   held_back         beyond that reach otherwise
--   idle_in_reach     within attack range + 300 and not attacking it
-- Distance is the creep_death `p<pos>d` when seen, else from the core's snapshot (an unseen creep has no attack fields).
-- Constants: reach 300 and default attack range 150 as @lasthit_cores; 800 and 3 s `judgement`; the pairing radius and window as
-- view creep_fate. Params: like, at (default 600).
-- ensure: ev_creep_death(team, kind, x, y, by, p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_snap(pid, t, x, y, alive, hp, hit, ed, ln, ld)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
cores AS MATERIALIZED (
    SELECT l.game_id, l.team, l.pos, l.pid FROM lineup l JOIN gm ON gm.game_id = l.game_id WHERE l.pos BETWEEN 1 AND 3
),
seen AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, c.team, c.x, c.y, 'seen' AS src, c."by" AS killer, f.fate,
        c.p1d, c.p1r, c.p1t, c.p1a, c.p2d, c.p2r, c.p2t, c.p2a, c.p3d, c.p3r, c.p3t, c.p3a
    FROM ev_creep_death c JOIN gm ON gm.game_id = c.game_id
    LEFT JOIN creep_fate f ON f.game_id = c.game_id AND f.seq = c.seq AND f.side = 'enemy'
    WHERE c.t < coalesce(:at, 600)
),
unseen AS MATERIALIZED (
    SELECT o.game_id, o.seq, o.t, 5 - o.team AS team, o.x, o.y, 'unseen' AS src, NULL AS killer,
        CASE WHEN CAST(o."by" AS TEXT) <> 'none' THEN 'enemy_deny' END AS fate,
        NULL AS p1d, NULL AS p1r, NULL AS p1t, NULL AS p1a, NULL AS p2d, NULL AS p2r, NULL AS p2t, NULL AS p2a,
        NULL AS p3d, NULL AS p3r, NULL AS p3t, NULL AS p3a
    FROM ev_own_creep_death o JOIN gm ON gm.game_id = o.game_id
    WHERE o.t < coalesce(:at, 600) AND o.team IN (2, 3)
      AND NOT EXISTS (SELECT 1 FROM ev_creep_death c WHERE c.game_id = o.game_id AND c.team <> o.team AND c.kind = o.kind
          AND c.t BETWEEN o.t - 1.0 AND o.t + 1.0 AND (c.x - o.x) * (c.x - o.x) + (c.y - o.y) * (c.y - o.y) <= 62500)
),
deaths AS MATERIALIZED (SELECT * FROM seen UNION ALL SELECT * FROM unseen),
csnap AS MATERIALIZED (
    SELECT s.game_id, s.seq, s.pid, s.t, s.x, s.y, s.hp, s.ed, s.hit, s.ln, s.ld
    FROM ev_snap s JOIN cores c ON c.game_id = s.game_id AND c.pid = s.pid
    WHERE s.t >= 0 AND s.t < coalesce(:at, 600) + 1 AND s.x IS NOT NULL AND s.alive IS NOT 0 AND s.hp > 0
),
pts AS (
    SELECT 'death' AS kind, d.src || ':' || d.seq AS k, d.seq, d.t, d.x, d.y FROM deaths d
    UNION ALL
    SELECT 'snap', 'snap:' || s.seq, s.seq, s.t, s.x, s.y FROM csnap s
),
-- include: lane_label
labs AS MATERIALIZED (SELECT k, lane FROM lab),
home AS MATERIALIZED (
    SELECT game_id, pid, lane FROM (
        SELECT s.game_id, s.pid, CAST(s.ln AS TEXT) AS lane,
            row_number() OVER (PARTITION BY s.game_id, s.pid ORDER BY count(*) DESC, CAST(s.ln AS TEXT)) AS rk
        FROM csnap s WHERE s.t >= 60 AND s.t < coalesce(:at, 600) AND s.ln IS NOT NULL AND s.ld < 1100
        GROUP BY s.game_id, s.pid, CAST(s.ln AS TEXT)
    ) WHERE rk = 1
),
dl AS MATERIALIZED (
    SELECT d.*, lb.lane,
        (SELECT c.pos FROM cores c JOIN home h ON h.game_id = c.game_id AND h.pid = c.pid
            WHERE c.game_id = d.game_id AND c.team = d.team AND h.lane = lb.lane ORDER BY c.pos LIMIT 1) AS cpos
    FROM deaths d JOIN labs lb ON lb.k = d.src || ':' || d.seq
),
dc AS MATERIALIZED (
    SELECT dl.*, c.pid AS cpid,
        CASE dl.cpos WHEN 1 THEN dl.p1d WHEN 2 THEN dl.p2d WHEN 3 THEN dl.p3d END AS pd,
        CASE dl.cpos WHEN 1 THEN dl.p1r WHEN 2 THEN dl.p2r WHEN 3 THEN dl.p3r END AS pr,
        CASE dl.cpos WHEN 1 THEN dl.p1t WHEN 2 THEN dl.p2t WHEN 3 THEN dl.p3t END AS pt,
        CASE dl.cpos WHEN 1 THEN dl.p1a WHEN 2 THEN dl.p2a WHEN 3 THEN dl.p3a END AS pa,
        (SELECT s.seq FROM csnap s WHERE s.game_id = dl.game_id AND s.pid = c.pid AND s.t BETWEEN dl.t - 2.5 AND dl.t + 0.5
            ORDER BY s.t DESC LIMIT 1) AS sseq
    FROM dl LEFT JOIN cores c ON c.game_id = dl.game_id AND c.team = dl.team AND c.pos = dl.cpos
),
dx AS (
    SELECT dc.*, s.hp, s.ed, cl.lane AS clane,
        coalesce(dc.pd, sqrt((s.x - dc.x) * (s.x - dc.x) + (s.y - dc.y) * (s.y - dc.y))) AS dist,
        EXISTS (SELECT 1 FROM csnap h WHERE h.game_id = dc.game_id AND h.pid = dc.cpid AND h.t BETWEEN dc.t - 3 AND dc.t + 0.5
            AND coalesce(h.hit, 0) > 0) AS hit3
    FROM dc LEFT JOIN csnap s ON s.game_id = dc.game_id AND s.seq = dc.sseq
    LEFT JOIN labs cl ON cl.k = 'snap:' || dc.sseq
)
SELECT gm.file, dx.game_id, dx.team, dx.t, dx.src, dx.lane, dx.cpos AS pos, dx.cpid AS pid, round(dx.dist) AS dist, dx.hp,
    dx.clane AS core_at,
    CASE WHEN dx.killer IS NOT NULL AND CAST(dx.killer AS TEXT) NOT IN ('none', 'deny') THEN 'taken'
         WHEN dx.fate = 'enemy_deny' OR CAST(dx.killer AS TEXT) = 'deny' THEN 'denied'
         WHEN dx.cpos IS NULL THEN 'off_lane'
         WHEN dx.sseq IS NULL THEN 'core_dead'
         WHEN dx.dist > 1500 AND coalesce(dx.clane, '') <> dx.lane THEN CASE WHEN dx.clane = 'base' THEN 'away_base' WHEN dx.clane = 'other' THEN 'away_jungle' ELSE 'away_lane' END
         WHEN dx.dist > 1500 THEN 'far_in_lane'
         WHEN dx.pt = 1 OR (typeof(dx.pa) IN ('integer', 'real') AND dx.pa >= 0) THEN 'swing_lost'
         WHEN dx.dist > coalesce(dx.pr, 150) + 300 THEN
             CASE WHEN dx.hit3 OR coalesce(dx.ed, 9999) <= 800 THEN 'held_back_hero'
                  WHEN dx.hp < 50 THEN 'held_back_low_hp'
                  ELSE 'held_back' END
         ELSE 'idle_in_reach' END AS cause
FROM dx JOIN gm ON gm.game_id = dx.game_id
ORDER BY gm.file, dx.t
