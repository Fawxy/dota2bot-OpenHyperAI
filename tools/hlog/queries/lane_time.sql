-- How each lineup hero spent its lane, one row per game and hero (slice lane-activity; method: docs/team/research/core-time-diagnosis.md).
-- Params: like (LIKE pattern on games.file, default every game), from and until (seconds, default 90 and 600).
-- Second counts are snaps from the view lane_activity (about 1 per second). hero, creep, retreat, lane, other: seconds per activity.
-- low_lane: seconds in laning below 35% HP; spike: seconds at the last-hit desire.
-- Choice against option (NULL on builds before the slice; for pos 3-5 a last hit on offer is one no allied core can reach): lh_open seconds with a last hit on offer and how many of them it was
-- attacking a creep (lh_open_creep); trade_open seconds with an enemy hero in range and no last hit on offer, and how many of them it
-- was attacking a hero (trade_open_hero); hit_noreply seconds hit by a hero with one in range and not attacking a hero.
-- near, taken: enemy lane creeps that died within 1,000 of the hero and those it got (pos 1-3 only: ev=creep_death has no p4, p5);
-- their ratio is conversion. Presence is near; a fall in last hits splits into near and taken / near.
-- ensure: ev_creep_death(team, by, p1d, p2d, p3d)
WITH gm AS MATERIALIZED (
    SELECT +game_id AS game_id, file FROM games
    WHERE max_t >= coalesce(:from, 90) AND file LIKE coalesce(:like, '%')
),
a AS (
    SELECT a.game_id, a.pid, a.team, a.pos,
        count(*) AS secs,
        sum(activity = 'hero') AS hero, sum(activity = 'creep') AS creep, sum(activity = 'retreat') AS retreat,
        sum(activity = 'lane') AS lane, sum(activity NOT IN ('hero', 'creep', 'retreat', 'lane')) AS other,
        sum(mode = 'laning' AND hp < 35) AS low_lane, sum(spike) AS spike,
        CASE WHEN count(ol) = 0 THEN NULL ELSE sum(ol > 0) END AS lh_open,
        CASE WHEN count(ol) = 0 THEN NULL ELSE sum(ol > 0 AND activity = 'creep') END AS lh_open_creep,
        CASE WHEN count(ol) = 0 THEN NULL ELSE sum(in_range AND ol = 0) END AS trade_open,
        CASE WHEN count(ol) = 0 THEN NULL ELSE sum(in_range AND ol = 0 AND activity = 'hero') END AS trade_open_hero,
        CASE WHEN count(hit) = 0 THEN NULL ELSE sum(hit = 1 AND in_range AND activity <> 'hero') END AS hit_noreply
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t < coalesce(:until, 600)
    GROUP BY a.game_id, a.pid, a.team, a.pos
),
cd AS (
    SELECT c.game_id, l.pid,
        sum(CASE l.pos WHEN 1 THEN c.p1d WHEN 2 THEN c.p2d ELSE c.p3d END <= 1000) AS near,
        sum(CASE l.pos WHEN 1 THEN c.p1d WHEN 2 THEN c.p2d ELSE c.p3d END <= 1000 AND CAST(c."by" AS TEXT) = CAST(l.pid AS TEXT)) AS taken
    FROM ev_creep_death c JOIN gm ON gm.game_id = c.game_id
    JOIN lineup l ON l.game_id = c.game_id AND l.team = c.team AND l.pos BETWEEN 1 AND 3
    WHERE c.t >= coalesce(:from, 90) AND c.t < coalesce(:until, 600)
    GROUP BY c.game_id, l.pid
)
SELECT gm.file, a.game_id, a.team, a.pos, a.pid, a.secs, a.hero, a.creep, a.retreat, a.lane, a.other, a.low_lane, a.spike,
    a.lh_open, a.lh_open_creep, a.trade_open, a.trade_open_hero, a.hit_noreply, cd.near, cd.taken
FROM a JOIN gm ON gm.game_id = a.game_id
LEFT JOIN cd ON cd.game_id = a.game_id AND cd.pid = a.pid
ORDER BY a.game_id, a.team, a.pos
