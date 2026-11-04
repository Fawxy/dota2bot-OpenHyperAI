-- Lane encounters (slice lane-fight): what an in-lane fight looked like at its start and how it ended, for the decider that
-- replaces team roam's lane fights. An encounter is a run of a lineup hero's live snaps from :from to :until (default 90-600)
-- with an enemy hero within 800 (`ed`), gaps up to 3 s, at least 2 snaps. At its first snap: allies and enemies alive within 1,200
-- of the hero (lineup snaps within 0.6 s), the lowest such enemy's HP and the hero's own. Outcome, to 5 s after its last snap:
-- died (the hero's death, dated at the snapshot before the dead gap, as fragment hero_death), kill (an enemy hero died within
-- 1,600 of the hero's mean position: a kill near it, not necessarily its own), hp_drop (the hero's HP-% range inside it).
-- held: `roam` when team roam or roam held the hero in 30% or more of its snaps, else `other`.
-- Params: like (LIKE pattern on games.file), from, until.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
sn AS MATERIALIZED (
    SELECT s.game_id, s.pid, l.team, l.pos, s.t, s.x, s.y, s.hp, s.deaths, s.mode, s.ed, s.alive
    FROM ev_snap s JOIN gm ON gm.game_id = s.game_id JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
    WHERE s.t BETWEEN coalesce(:from, 90) - 10 AND coalesce(:until, 600) + 40 AND s.x IS NOT NULL
),
dd AS MATERIALIZED (
    SELECT game_id, pid, team, pt AS t, px AS x, py AS y FROM (
        SELECT *, lag(t) OVER w AS pt, lag(x) OVER w AS px, lag(y) OVER w AS py, lag(deaths) OVER w AS pd
        FROM sn WINDOW w AS (PARTITION BY game_id, pid ORDER BY t))
    WHERE deaths > pd AND t - pt > 2.5
),
a AS (
    SELECT *, (ed IS NOT NULL AND ed <= 800) AS near, mode IN ('team_roam', 'roam') AS fm
    FROM sn WHERE t BETWEEN coalesce(:from, 90) AND coalesce(:until, 600) AND alive IS NOT 0
),
m AS (
    SELECT *, CASE WHEN near AND (lag(near) OVER w IS NOT 1 OR t - lag(t) OVER w > 3) THEN 1 ELSE 0 END AS st
    FROM a WINDOW w AS (PARTITION BY game_id, pid ORDER BY t)
),
g AS (SELECT *, sum(st) OVER (PARTITION BY game_id, pid ORDER BY t) AS ep FROM m),
e AS (
    SELECT game_id, pid, team, pos, min(t) AS t0, max(t) AS t1, count(*) AS secs, sum(fm) AS fm_s,
        max(hp) - min(hp) AS hp_drop, avg(x) AS x, avg(y) AS y
    FROM g WHERE near AND ep > 0 GROUP BY game_id, pid, team, pos, ep HAVING count(*) >= 2
),
f AS (
    SELECT e.*, s0.x AS x0, s0.y AS y0, s0.hp AS hp0,
        EXISTS (SELECT 1 FROM dd WHERE dd.game_id = e.game_id AND dd.pid = e.pid AND dd.t BETWEEN e.t0 AND e.t1 + 5) AS died,
        EXISTS (SELECT 1 FROM dd WHERE dd.game_id = e.game_id AND dd.team <> e.team AND dd.t BETWEEN e.t0 AND e.t1 + 5
            AND (dd.x - e.x) * (dd.x - e.x) + (dd.y - e.y) * (dd.y - e.y) < 1600 * 1600) AS kill
    FROM e JOIN ev_snap s0 ON s0.game_id = e.game_id AND s0.pid = e.pid AND s0.t = e.t0
),
n AS (
    SELECT f.*,
        (SELECT count(*) FROM lineup l2 JOIN ev_snap o ON o.game_id = l2.game_id AND o.pid = l2.pid AND o.t BETWEEN f.t0 - 0.6 AND f.t0 + 0.6
            WHERE l2.game_id = f.game_id AND l2.team = f.team AND l2.pid <> f.pid AND o.alive IS NOT 0
            AND (o.x - f.x0) * (o.x - f.x0) + (o.y - f.y0) * (o.y - f.y0) < 1200 * 1200) AS al,
        (SELECT count(*) FROM lineup l2 JOIN ev_snap o ON o.game_id = l2.game_id AND o.pid = l2.pid AND o.t BETWEEN f.t0 - 0.6 AND f.t0 + 0.6
            WHERE l2.game_id = f.game_id AND l2.team <> f.team AND o.alive IS NOT 0
            AND (o.x - f.x0) * (o.x - f.x0) + (o.y - f.y0) * (o.y - f.y0) < 1200 * 1200) AS en,
        (SELECT min(o.hp) FROM lineup l2 JOIN ev_snap o ON o.game_id = l2.game_id AND o.pid = l2.pid AND o.t BETWEEN f.t0 - 0.6 AND f.t0 + 0.6
            WHERE l2.game_id = f.game_id AND l2.team <> f.team AND o.alive IS NOT 0
            AND (o.x - f.x0) * (o.x - f.x0) + (o.y - f.y0) * (o.y - f.y0) < 1200 * 1200) AS ehp
    FROM f
)
SELECT CASE WHEN pos <= 3 THEN 'core' ELSE 'sup' END AS role,
    CASE WHEN al + 1 > en THEN 'more' WHEN al + 1 = en THEN 'even' ELSE 'fewer' END AS numbers,
    CASE WHEN ehp IS NULL THEN '?' WHEN ehp <= 40 THEN '<=40' WHEN ehp <= 70 THEN '<=70' ELSE '>70' END AS ehp,
    CASE WHEN fm_s * 1.0 / secs >= 0.3 THEN 'roam' ELSE 'other' END AS held,
    count(*) AS enc, sum(kill) AS kills, sum(died) AS deaths, round(avg(hp_drop), 1) AS hp_drop, round(avg(hp0), 0) AS hp0,
    sum(secs) AS secs, sum(fm_s) AS roam_s
FROM n GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4
