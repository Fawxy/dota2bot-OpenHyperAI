-- Idle HP lost by the nearest enemy hero (slice lane-positioning step 1c: how far back the spot's hero limit must keep a core).
-- One row per enemy kind, core kind, distance band and spot band, :from to :until (default 90-600), lineup cores pos 1-3.
-- Idle is @core_spot's: laning with no attack target, less the seconds the laning body walked to a last hit or deny.
-- The nearest enemy is the closest alive enemy lineup hero by its own ev=snap in the same second (any state, fogged or not),
-- not the snapshot's `ed` (visible heroes only).
--   ek, me      melee (attack range 200 or less) or ranged: the nearest enemy (its `ar`) and the core itself
--   band        distance to that enemy: 0-600, 600-800, 800-1000, 1000+
--   spot        on (ev=lane_pos `d` 300 or less), off, or `?` (no sample); a sample covers its second and, when no sample lands
--               there, the next (lane_pos every 2 s before step 1c, every 1 s since), as in @core_spot
-- Core and enemy snapshots are matched by rounded second; seconds with no alive enemy lineup hero are dropped.
--   secs, hpl   idle seconds and HP-% points lost from each to the next snapshot;  hpl_s  per second
--   hit         seconds whose next snapshot flags a hero hit (`hit` covers the second before its snapshot)
-- Params: like, from, until.
-- ensure: ev_lane_pos(pid, label, d)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
s AS MATERIALIZED (
    SELECT s.game_id, s.pid, l.team, CAST(round(s.t) AS INTEGER) AS sec, max(s.x) AS x, max(s.y) AS y, max(s.ar) AS ar
    FROM ev_snap s JOIN gm ON gm.game_id = s.game_id JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
    WHERE s.t >= coalesce(:from, 90) - 1 AND s.t <= coalesce(:until, 600) + 1 AND s.alive = 1
    GROUP BY 1, 2, 3, 4
),
a AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.team, CAST(round(a.t) AS INTEGER) AS sec, a.x, a.y, a.hp, a.ar, a.activity,
        lead(a.hp) OVER w AS nhp, lead(a.hit) OVER w AS nhit
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.pos <= 3 AND a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
    WINDOW w AS (PARTITION BY a.game_id, a.pid ORDER BY a.t)
),
lp AS MATERIALIZED (
    SELECT game_id, pid, sec, lh, d, lead(sec) OVER (PARTITION BY game_id, pid ORDER BY sec) AS nsec
    FROM (SELECT lp.game_id, lp.pid, CAST(round(lp.t) AS INTEGER) AS sec, max(lp.label IN ('lasthit', 'deny')) AS lh, max(lp.d) AS d
          FROM ev_lane_pos lp JOIN gm ON gm.game_id = lp.game_id GROUP BY 1, 2, 3)
),
lc AS MATERIALIZED (
    SELECT game_id, pid, sec, lh, d FROM lp
    UNION ALL SELECT game_id, pid, sec + 1, lh, d FROM lp WHERE nsec IS NULL OR nsec > sec + 1
),
i AS MATERIALIZED (
    SELECT a.*, CASE WHEN a.nhp IS NULL THEN 0 ELSE max(0, a.hp - a.nhp) END AS lost, lc.d AS sd
    FROM a LEFT JOIN lc ON lc.game_id = a.game_id AND lc.pid = a.pid AND lc.sec = a.sec
    WHERE a.activity = 'lane' AND NOT coalesce(lc.lh, 0)
),
e AS (
    SELECT i.*, e.ar AS ear, sqrt((e.x - i.x) * (e.x - i.x) + (e.y - i.y) * (e.y - i.y)) AS d,
        row_number() OVER (PARTITION BY i.game_id, i.pid, i.sec ORDER BY (e.x - i.x) * (e.x - i.x) + (e.y - i.y) * (e.y - i.y)) AS rk
    FROM i JOIN s e ON e.game_id = i.game_id AND e.sec = i.sec AND e.team <> i.team
)
SELECT CASE WHEN ear <= 200 THEN 'melee' ELSE 'ranged' END AS ek, CASE WHEN ar <= 200 THEN 'melee' ELSE 'ranged' END AS me,
    CASE WHEN d < 600 THEN '0-600' WHEN d < 800 THEN '600-800' WHEN d < 1000 THEN '800-1000' ELSE '1000+' END AS band,
    CASE WHEN sd IS NULL THEN '?' WHEN sd <= 300 THEN 'on' ELSE 'off' END AS spot,
    count(*) AS secs, round(sum(lost), 1) AS hpl, round(sum(lost) * 1.0 / count(*), 2) AS hpl_s, sum(coalesce(nhit, 0)) AS hit
FROM e WHERE rk = 1
GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, min(d), 4
