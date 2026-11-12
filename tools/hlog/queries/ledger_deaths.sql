-- Every hero death before :until with one cause from what happened in the 10 s before it (the loss ledger, rework step 6; read
-- through ledger.js, which sets pos_lo 1, pos_hi 5 and until 720). The death rule is fragment core_death's. First match wins:
--   tower              an enemy tower targeted the hero in its last 5 s (it stood in their tower's range)
--   outnumbered_alone  two or more enemy heroes attacked it, no ally in the fight (below)
--   outnumbered        more enemy heroes attacked it than we had in the fight (itself included)
--   duel               one enemy hero attacked it, no ally in the fight
--   even_numbers       enemy heroes attacked it and we had as many heroes in the fight or more (fighting back or not)
--   creeps             no enemy hero attack seen, lane creeps or neutrals targeted it
--   unexplained        none of these (spells cast from outside the window, fog)
-- attackers: the largest of three counts over the window: distinct enemy heroes whose snapshot `tid` named this hero, the
-- hero's own largest `ah` (enemy heroes targeting it within 1,600), and the enemy heroes alive within 1,000 of it at a second it
-- was hit by a hero (`hit`): the first two see attacks only, the third the casters too. Needs builds with the damage fields
-- (`ah`, from slice hit-back's era); older logs read their deaths `unexplained` or `even_numbers`. hp10: HP percent at the
-- snapshot nearest 10 s before. Params: like (a path fragment), until, pos_lo, pos_hi.
-- ensure: ev_snap(pid, t, tid, ah, ac, an, at, hit, hc, hp, alive, x, y)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: core_death
dd AS MATERIALIZED (SELECT game_id, pid, team, pos, t, x, y FROM cd),
vs AS MATERIALIZED (
    SELECT dd.game_id, dd.pid, dd.t, max(coalesce(s.ah, 0)) AS ah,
        max(CASE WHEN s.t >= dd.t - 5 THEN coalesce(s.at, 0) ELSE 0 END) AS tower5,
        max(coalesce(s.ac, 0) + coalesce(s.an, 0)) AS creeps, max(coalesce(s.hc, 0)) AS hc
    FROM dd JOIN ev_snap s ON s.game_id = dd.game_id AND s.pid = dd.pid AND s.t BETWEEN dd.t - 10 AND dd.t
    GROUP BY dd.game_id, dd.pid, dd.t
),
ta AS MATERIALIZED (
    SELECT dd.game_id, dd.pid, dd.t, count(DISTINCT s.pid) AS n
    FROM dd JOIN lineup l ON l.game_id = dd.game_id AND l.team <> dd.team
    JOIN ev_snap s ON s.game_id = l.game_id AND s.pid = l.pid AND s.t BETWEEN dd.t - 10 AND dd.t + 0.5
    WHERE CAST(s.tid AS TEXT) = 'h' || dd.pid
    GROUP BY dd.game_id, dd.pid, dd.t
),
-- Allies in the fight: our heroes within 1,200 of the hero on at least half of the window's seconds it was hit by a hero (at the
-- death alone when it was never hit by one): a partner it fled toward and reached as it died does not count.
hs AS MATERIALIZED (
    SELECT dd.game_id, dd.pid, dd.t, v.t AS vt, v.x, v.y
    FROM dd JOIN ev_snap v ON v.game_id = dd.game_id AND v.pid = dd.pid AND v.t BETWEEN dd.t - 10 AND dd.t
    WHERE coalesce(v.hit, 0) > 0
),
hn AS MATERIALIZED (SELECT game_id, pid, t, count(*) AS n FROM hs GROUP BY game_id, pid, t),
al AS MATERIALIZED (
    SELECT game_id, pid, t, count(*) AS n FROM (
        SELECT hs.game_id, hs.pid, hs.t, a.pid AS apid, count(DISTINCT hs.vt) AS k, hn.n
        FROM hs JOIN hn ON hn.game_id = hs.game_id AND hn.pid = hs.pid AND hn.t = hs.t
        JOIN lineup l ON l.game_id = hs.game_id AND l.team = (SELECT team FROM dd WHERE dd.game_id = hs.game_id AND dd.pid = hs.pid AND dd.t = hs.t)
            AND l.pid <> hs.pid
        JOIN ev_snap a ON a.game_id = l.game_id AND a.pid = l.pid AND a.t BETWEEN hs.vt - 0.6 AND hs.vt + 0.6
        WHERE a.alive IS NOT 0 AND (a.x - hs.x) * (a.x - hs.x) + (a.y - hs.y) * (a.y - hs.y) <= 1200 * 1200
        GROUP BY hs.game_id, hs.pid, hs.t, a.pid
    ) WHERE 2 * k >= n GROUP BY game_id, pid, t
    UNION ALL
    SELECT dd.game_id, dd.pid, dd.t, count(DISTINCT s.pid)
    FROM dd JOIN lineup l ON l.game_id = dd.game_id AND l.team = dd.team AND l.pid <> dd.pid
    JOIN ev_snap s ON s.game_id = l.game_id AND s.pid = l.pid AND s.t BETWEEN dd.t - 1 AND dd.t + 0.5
    WHERE NOT EXISTS (SELECT 1 FROM hn WHERE hn.game_id = dd.game_id AND hn.pid = dd.pid AND hn.t = dd.t)
      AND s.alive IS NOT 0 AND (s.x - dd.x) * (s.x - dd.x) + (s.y - dd.y) * (s.y - dd.y) <= 1200 * 1200
    GROUP BY dd.game_id, dd.pid, dd.t
),
-- Present: enemy heroes alive within 1,000 at a second the hero was hit by a hero (spells: `ah` and `tid` see attacks only).
pr AS MATERIALIZED (
    SELECT dd.game_id, dd.pid, dd.t, count(DISTINCT e.pid) AS n
    FROM dd JOIN ev_snap v ON v.game_id = dd.game_id AND v.pid = dd.pid AND v.t BETWEEN dd.t - 10 AND dd.t AND coalesce(v.hit, 0) > 0
    JOIN lineup l ON l.game_id = dd.game_id AND l.team <> dd.team
    JOIN ev_snap e ON e.game_id = l.game_id AND e.pid = l.pid AND e.t BETWEEN v.t - 0.6 AND v.t + 0.6
    WHERE e.alive IS NOT 0 AND (e.x - v.x) * (e.x - v.x) + (e.y - v.y) * (e.y - v.y) <= 1000 * 1000
    GROUP BY dd.game_id, dd.pid, dd.t
),
hp10 AS MATERIALIZED (
    SELECT game_id, pid, t, hp FROM (
        SELECT dd.game_id, dd.pid, dd.t, s.hp, row_number() OVER (PARTITION BY dd.game_id, dd.pid, dd.t ORDER BY abs(s.t - (dd.t - 10))) AS rk
        FROM dd JOIN ev_snap s ON s.game_id = dd.game_id AND s.pid = dd.pid AND s.t BETWEEN dd.t - 12 AND dd.t - 8
    ) WHERE rk = 1
),
f AS (
    SELECT dd.*, vs.tower5, vs.creeps, vs.hc, max(vs.ah, coalesce(ta.n, 0), coalesce(pr.n, 0)) AS attackers, coalesce(al.n, 0) AS allies, hp10.hp AS hp10
    FROM dd JOIN vs ON vs.game_id = dd.game_id AND vs.pid = dd.pid AND vs.t = dd.t
    LEFT JOIN ta ON ta.game_id = dd.game_id AND ta.pid = dd.pid AND ta.t = dd.t
    LEFT JOIN pr ON pr.game_id = dd.game_id AND pr.pid = dd.pid AND pr.t = dd.t
    LEFT JOIN al ON al.game_id = dd.game_id AND al.pid = dd.pid AND al.t = dd.t
    LEFT JOIN hp10 ON hp10.game_id = dd.game_id AND hp10.pid = dd.pid AND hp10.t = dd.t
)
SELECT gm.file, f.game_id, f.team, f.pos, f.pid, f.t, f.attackers, f.allies, f.hp10,
    CASE WHEN f.tower5 >= 1 THEN 'tower'
         WHEN f.attackers >= 2 AND f.allies = 0 THEN 'outnumbered_alone'
         WHEN f.attackers > f.allies + 1 THEN 'outnumbered'
         WHEN f.attackers >= 1 AND f.allies = 0 THEN 'duel'
         WHEN f.attackers >= 1 THEN 'even_numbers'
         WHEN f.creeps >= 1 OR f.hc THEN 'creeps'
         ELSE 'unexplained' END AS cause
FROM f JOIN gm ON gm.game_id = f.game_id
ORDER BY gm.file, f.t
