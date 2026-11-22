-- The timeline: one row per thing that happened (time, hero, kind, detail), by lane, hero, time and kind.
-- `node hlog.js timeline` is its text view. The six episodes have one definition each, in the fragment named:
--   death      ep_death      the hero's last living moment, with who attacked it in the 10 s before
--   retreat    ep_retreat    a retreat bout
--   exchange   ep_exchange   two opposing heroes attacking; `hero` struck first
--   kill_try   ep_kill       a kill attempt; `hero` is its first attacker
--   job        ep_job        a job trip
--   visit      ep_visit      a lane visit
-- To read between them:
--   mode       a mode other than retreat held 3 s or more (from the snapshots, so stock logs have it too)
--   cast       an ability cast (no target is logged)
--   creep      a last hit or a deny
--   state      every 15 s: HP, mode, the nearest living enemy, allies within 1,200
--   not_logged what this log cannot show, so that none is not read as zero: first, whatever the lane, hero or window
-- Columns: file, game, t, t1 (NULL: a moment, or a trip with no end), lane (at t: top, mid, bot, base or other; a visit's own),
-- team, pos, pid, hero, kind, detail, who (every hero in the row, as `,luna,lich,`).
-- A row is in the window when any part of it is; a lane's rows are those that began there.
-- Params: like (a path fragment or run label; required), game (default each log's last), lane, hero (either party), pid,
-- from, to (seconds), kind (comma separated).
-- ensure: ev_cast(pid, ab)
-- ensure: ev_creep_death(team, kind, by)
-- ensure: ev_own_creep_death(team, kind, by)
-- ensure: ev_neutral_death(team, by)
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id, g.file, g.game FROM games g
    WHERE g.file LIKE coalesce(:like, '')
        AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file))
),
-- The whole game, whatever the window: an episode that crosses the window's edge keeps its real start and end.
ep_win AS (SELECT -1e9 AS lo, 1e9 AS hi),
-- include: ep_retreat
-- include: ep_exchange
-- include: ep_kill
-- include: ep_job
-- include: ep_visit
-- Who attacked: per death in its last 10 s, and per kill attempt.
tl_by_death AS MATERIALIZED (
    SELECT game_id, pid, t, group_concat(hero, ', ') AS names, group_concat(hero, ',') AS list FROM (
        SELECT DISTINCT d.game_id, d.pid, d.t, w.pid AS apid, w.hero
        FROM ep_death d
        JOIN ep_hit h ON h.game_id = d.game_id AND h.tpid = d.pid AND h.sec BETWEEN d.t - 10 AND d.t + 1
        JOIN ep_who w ON w.game_id = h.game_id AND w.pid = h.apid
        ORDER BY 1, 2, 3, 4
    ) GROUP BY game_id, pid, t
),
tl_by_kill AS MATERIALIZED (
    SELECT game_id, team, tpid, t0, group_concat(hero, ', ') AS names, group_concat(hero, ',') AS list FROM (
        SELECT DISTINCT k.game_id, k.team, k.tpid, k.t0, w.pid AS apid, w.hero
        FROM ep_kill k
        JOIN ep_hit h ON h.game_id = k.game_id AND h.team = k.team AND h.tpid = k.tpid AND h.sec BETWEEN k.t0 AND k.t1
        JOIN ep_who w ON w.game_id = h.game_id AND w.pid = h.apid
        ORDER BY 1, 2, 3, 4, 5
    ) GROUP BY game_id, team, tpid, t0
),
tl_death AS (
    SELECT d.game_id, d.pid, d.t, NULL AS t1, 'death' AS kind,
        'died in ' || coalesce(s.mode, '?') || coalesce('; attacked by ' || b.names, '')
            || CASE WHEN d.open THEN '; still dead at the log''s end' ELSE '' END AS detail,
        coalesce(b.list, '') AS others, NULL AS in_lane
    FROM ep_death d
    LEFT JOIN ep_sec s ON s.game_id = d.game_id AND s.pid = d.pid AND s.sec = CAST(round(d.t) AS INTEGER)
    LEFT JOIN tl_by_death b ON b.game_id = d.game_id AND b.pid = d.pid AND b.t = d.t
),
tl_retreat AS (
    SELECT r.game_id, r.pid, r.t0, r.t1, 'retreat',
        'hp ' || coalesce(a.hp, '?') || ' to ' || coalesce(z.hp, '?') || ' (low ' || coalesce(r.hpmin, '?') || ')'
            || CASE WHEN EXISTS (SELECT 1 FROM ep_gap d WHERE d.game_id = r.game_id AND d.pid = r.pid AND d.dsec BETWEEN r.t0 AND r.t1 + 3)
                THEN '; died' ELSE '' END,
        '', NULL
    FROM ep_retreat r
    JOIN ep_sec a ON a.game_id = r.game_id AND a.pid = r.pid AND a.sec = r.t0
    JOIN ep_sec z ON z.game_id = r.game_id AND z.pid = r.pid AND z.sec = r.t1
),
tl_exchange AS (
    SELECT e.game_id, e.a, e.t0, e.t1, 'exchange',
        'on ' || coalesce(w.hero, e.b) || ', ' || e.a_secs || ' s of attacks, '
            || CASE WHEN e.b_secs > 0 THEN e.b_secs || ' s back' ELSE 'none back' END
            || '; hp ' || coalesce(a0.hp, '?') || ' to ' || coalesce(a1.hp, '?')
            || ', theirs ' || coalesce(b0.hp, '?') || ' to ' || coalesce(b1.hp, '?'),
        coalesce(w.hero, ''), NULL
    FROM ep_exchange e
    JOIN ep_who w ON w.game_id = e.game_id AND w.pid = e.b
    LEFT JOIN ep_sec a0 ON a0.game_id = e.game_id AND a0.pid = e.a AND a0.sec = e.t0
    LEFT JOIN ep_sec a1 ON a1.game_id = e.game_id AND a1.pid = e.a AND a1.sec = e.t1
    LEFT JOIN ep_sec b0 ON b0.game_id = e.game_id AND b0.pid = e.b AND b0.sec = e.t0
    LEFT JOIN ep_sec b1 ON b1.game_id = e.game_id AND b1.pid = e.b AND b1.sec = e.t1
),
tl_kill AS (
    SELECT k.game_id,
        (SELECT h.apid FROM ep_hit h
            WHERE h.game_id = k.game_id AND h.team = k.team AND h.tpid = k.tpid AND h.sec = k.t0 ORDER BY h.apid LIMIT 1),
        k.t0, k.t1, 'kill_try',
        'on ' || coalesce(w.hero, k.tpid) || ' by ' || coalesce(b.names, '?')
            || CASE WHEN k.killed THEN ': killed' ELSE ': lived, low ' || coalesce(k.hpmin, '?') END,
        coalesce(w.hero, '') || coalesce(',' || b.list, ''), NULL
    FROM ep_kill k
    JOIN ep_who w ON w.game_id = k.game_id AND w.pid = k.tpid
    LEFT JOIN tl_by_kill b ON b.game_id = k.game_id AND b.team = k.team AND b.tpid = k.tpid AND b.t0 = k.t0
),
tl_job AS (
    SELECT game_id, pid, t0, t1, 'job',
        coalesce(job, src) || ': ' || CASE WHEN t1 IS NULL THEN 'no end logged' ELSE coalesce(why, 'ended') END, '', NULL
    FROM ep_job
),
tl_visit AS (
    SELECT v.game_id, v.pid, v.t0, v.t1, 'visit',
        'in ' || v.lane || ', ends ' || CASE
            WHEN EXISTS (SELECT 1 FROM ep_gap d WHERE d.game_id = v.game_id AND d.pid = v.pid AND d.dsec BETWEEN v.t1 - 1 AND v.t1 + 2)
                THEN 'dead'
            ELSE 'in ' || coalesce(s.mode, '?') END,
        '', v.lane
    FROM ep_visit v LEFT JOIN ep_sec s ON s.game_id = v.game_id AND s.pid = v.pid AND s.sec = v.t1
),
tl_mode0 AS (
    SELECT s.game_id, s.pid, s.sec, s.mode, s.life,
        CASE WHEN s.mode = lag(s.mode) OVER w AND s.sec - lag(s.sec) OVER w <= 2 THEN 0 ELSE 1 END AS brk
    FROM ep_sec s WHERE s.live
    WINDOW w AS (PARTITION BY s.game_id, s.pid, s.life ORDER BY s.sec)
),
tl_mode AS (
    SELECT game_id, pid, min(sec), max(sec), 'mode', mode, '', NULL
    FROM (SELECT m.*, sum(brk) OVER (PARTITION BY game_id, pid, life ORDER BY sec) AS k FROM tl_mode0 m)
    GROUP BY game_id, pid, life, k HAVING max(sec) - min(sec) >= 2 AND mode <> 'retreat'
),
tl_cast AS (
    SELECT c.game_id, c.pid, c.t, NULL, 'cast', c.ab, '', NULL
    FROM gm CROSS JOIN ev_cast c ON c.game_id = gm.game_id WHERE c.ab IS NOT NULL
),
-- `by` is a pid only on a creep a hero got.
tl_got AS (
    SELECT c.game_id, c.t, c.team, c."by" AS got, 'last hit ' || coalesce(c.kind, 'creep') AS what
    FROM gm CROSS JOIN ev_creep_death c ON c.game_id = gm.game_id
    UNION ALL
    SELECT c.game_id, c.t, c.team, c."by", 'deny ' || coalesce(c.kind, 'creep')
    FROM gm CROSS JOIN ev_own_creep_death c ON c.game_id = gm.game_id
    UNION ALL
    SELECT c.game_id, c.t, c.team, c."by", 'last hit neutral'
    FROM gm CROSS JOIN ev_neutral_death c ON c.game_id = gm.game_id
),
tl_creep AS (
    SELECT c.game_id, w.pid, c.t, NULL, 'creep', c.what, '', NULL
    FROM tl_got c JOIN ep_who w ON w.game_id = c.game_id AND w.team = c.team AND CAST(c.got AS TEXT) = CAST(w.pid AS TEXT)
),
tl_state AS (
    SELECT s.game_id, s.pid, s.sec, NULL, 'state',
        'hp ' || coalesce(s.hp, '?') || ', ' || coalesce(s.mode, '?') || ', enemy '
            || coalesce(CAST(round(sqrt(min(CASE WHEN o.team <> s.team
                THEN (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) END))) AS INTEGER), '?')
            || ', allies '
            || coalesce(sum(o.team = s.team AND (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) <= 1200 * 1200), 0),
        '', NULL
    FROM ep_sec s LEFT JOIN ep_sec o ON o.game_id = s.game_id AND o.sec = s.sec AND o.pid <> s.pid AND o.live
    WHERE s.live AND s.sec % 15 = 0
    GROUP BY s.game_id, s.pid, s.sec
),
tl_all AS (
    SELECT * FROM tl_death
    UNION ALL SELECT * FROM tl_retreat
    UNION ALL SELECT * FROM tl_exchange
    UNION ALL SELECT * FROM tl_kill
    UNION ALL SELECT * FROM tl_job
    UNION ALL SELECT * FROM tl_visit
    UNION ALL SELECT * FROM tl_mode
    UNION ALL SELECT * FROM tl_cast
    UNION ALL SELECT * FROM tl_creep
    UNION ALL SELECT * FROM tl_state
),
tl_in AS MATERIALIZED (
    SELECT a.*, w.team, w.pos, w.hero, CAST(round(a.t) AS INTEGER) AS sec
    FROM tl_all a JOIN ep_who w ON w.game_id = a.game_id AND w.pid = a.pid
    WHERE a.t <= coalesce(:to, 1e9) AND coalesce(a.t1, a.t) >= coalesce(:from, -1e9)
        AND (:kind IS NULL OR instr(',' || :kind || ',', ',' || a.kind || ',') > 0)
        AND (:pid IS NULL OR a.pid = :pid)
        AND (:hero IS NULL OR w.hero = :hero OR instr(',' || a.others || ',', ',' || :hero || ',') > 0)
),
-- A moment a half second past the last live one (a death, a cast) takes the second before's place.
tl_row AS (
    SELECT i.*, coalesce(i.in_lane, p.lane, p1.lane, 'other') AS lane
    FROM tl_in i
    LEFT JOIN ep_place p ON p.game_id = i.game_id AND p.pid = i.pid AND p.sec = i.sec
    LEFT JOIN ep_place p1 ON p1.game_id = i.game_id AND p1.pid = i.pid AND p1.sec = i.sec - 1
),
-- What each team's log lacks, judged per team: the two sides of a game can run different builds.
tl_team (team, name) AS (VALUES (2, 'Radiant'), (3, 'Dire')),
tl_lack AS (
    SELECT g.game_id, t.team, 'exchange,kill_try' AS kinds, t.name || ': no attack target (tid) in the log, so its attacks are not seen' AS detail
    FROM gm g, tl_team t
    WHERE EXISTS (SELECT 1 FROM ep_sec s WHERE s.game_id = g.game_id AND s.team = t.team)
        AND NOT EXISTS (SELECT 1 FROM ep_sec s WHERE s.game_id = g.game_id AND s.team = t.team AND s.tid IS NOT NULL)
    UNION ALL
    SELECT g.game_id, t.team, 'death,retreat,exchange,kill_try,visit,mode,state', t.name || ': no snapshots in the log'
    FROM gm g, tl_team t
    WHERE NOT EXISTS (SELECT 1 FROM ep_sec s WHERE s.game_id = g.game_id AND s.team = t.team)
    UNION ALL
    SELECT g.game_id, t.team, 'cast', t.name || ': no casts in the log'
    FROM gm g, tl_team t
    WHERE NOT EXISTS (SELECT 1 FROM ev_cast c JOIN ep_who w ON w.game_id = c.game_id AND w.pid = c.pid
        WHERE c.game_id = g.game_id AND w.team = t.team AND c.ab IS NOT NULL)
    UNION ALL
    SELECT g.game_id, t.team, 'creep', t.name || ': no creep deaths in the log'
    FROM gm g, tl_team t
    WHERE NOT EXISTS (SELECT 1 FROM ev_creep_death c WHERE c.game_id = g.game_id AND c.team = t.team)
),
tl_kinds (kind) AS (VALUES ('death'), ('retreat'), ('exchange'), ('kill_try'), ('visit'), ('mode'), ('state'), ('cast'), ('creep'))
SELECT gm.file, gm.game, o.t, o.t1, o.lane, o.team, o.pos, o.pid, o.hero, o.kind, o.detail, o.who
FROM (
    SELECT game_id, round(t, 1) AS t, round(t1, 1) AS t1, lane, team, pos, pid, hero, kind, detail,
        ',' || hero || ',' || CASE WHEN others = '' THEN '' ELSE others || ',' END AS who
    FROM tl_row WHERE :lane IS NULL OR lane = :lane
    UNION ALL
    SELECT game_id, NULL, NULL, NULL, team, NULL, NULL, NULL, 'not_logged', detail, NULL
    FROM tl_lack l
    WHERE :kind IS NULL OR EXISTS (
        SELECT 1 FROM tl_kinds k
        WHERE instr(',' || l.kinds || ',', ',' || k.kind || ',') > 0 AND instr(',' || :kind || ',', ',' || k.kind || ',') > 0)
) o JOIN gm ON gm.game_id = o.game_id
ORDER BY gm.file, o.t IS NOT NULL, o.t, o.pid, o.kind
