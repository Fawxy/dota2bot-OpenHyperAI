-- Fragment (`-- include: timeline_rows`): the rows of query timeline, so that any query can count them:
--   -- include: timeline_rows
--   SELECT arm, side, count(*) FROM timeline_rows WHERE kind = 'death' GROUP BY arm, side
-- (the include tolerates the comma this fragment ends with when a SELECT follows it). CTE `timeline_rows` has the columns the
-- header of query timeline lists, unordered. It defines `gm` (the games read) and `ep_win` (the whole game) itself, from the
-- params of query timeline: like or batch, arm, game, lane, hero, pid, from, to, kind. Ends with a comma.
-- ensure: ev_cast(pid, ab)
-- ensure: ev_creep_death(team, kind, by)
-- ensure: ev_choice(pid, kind, want, go, why, src, lane, slot, aid)
gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id, g.file, g.game, r.batch, r.lineup, r.arm, r.seat_team, r.seat, r.rep
    FROM games g JOIN run_label r ON r.game_id = g.game_id
    WHERE g.file LIKE coalesce(:like, CASE WHEN :batch IS NULL THEN '' ELSE '%' END)
        AND (:batch IS NULL OR r.batch = :batch) AND (:arm IS NULL OR r.arm = :arm)
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
-- A death's cause is the loss ledger's rule (fragment death_cause), on every death, a hero still dead at the log's end included.
-- A kind filter without death or creep skips that kind's work (a constant WHERE: SQLite tests it once, before any row).
dc_in AS MATERIALIZED (
    SELECT d.game_id, d.pid, w.team, w.pos, d.t, d.x, d.y FROM ep_death d JOIN ep_who w ON w.game_id = d.game_id AND w.pid = d.pid
    WHERE :kind IS NULL OR instr(',' || :kind || ',', ',death,') > 0
),
-- ep_who's pos is view lineup's (the hero a team's pos names), so its heroes with a pos are lineup's rows for these games.
dc_lineup AS MATERIALIZED (SELECT game_id, team, pos, pid FROM ep_who WHERE pos IS NOT NULL AND game_id IN (SELECT game_id FROM dc_in)),
-- include: death_cause
tl_death AS (
    SELECT d.game_id, d.pid, d.t, NULL AS t1, 'death' AS kind,
        'died in ' || coalesce(s.mode, '?') || coalesce(': ' || c.cause, '') || coalesce('; attacked by ' || b.names, '')
            || CASE WHEN d.open THEN '; still dead at the log''s end' ELSE '' END AS detail,
        coalesce(b.list, '') AS others, NULL AS in_lane,
        NULL AS other_pid, 'died' AS outcome, NULL AS a_secs, NULL AS b_secs, NULL AS hpmin,
        NULL AS what, c.cause AS why, NULL AS slot
    FROM ep_death d
    LEFT JOIN ep_sec s ON s.game_id = d.game_id AND s.pid = d.pid AND s.sec = CAST(round(d.t) AS INTEGER)
    LEFT JOIN tl_by_death b ON b.game_id = d.game_id AND b.pid = d.pid AND b.t = d.t
    LEFT JOIN death_cause c ON c.game_id = d.game_id AND c.pid = d.pid AND c.t = d.t
    WHERE :kind IS NULL OR instr(',' || :kind || ',', ',death,') > 0
),
tl_ret AS (
    SELECT r.*, EXISTS (SELECT 1 FROM ep_gap d WHERE d.game_id = r.game_id AND d.pid = r.pid AND d.dsec BETWEEN r.t0 AND r.t1 + 3) AS died
    FROM ep_retreat r
),
tl_retreat AS (
    SELECT r.game_id, r.pid, r.t0, r.t1, 'retreat',
        'hp ' || coalesce(a.hp, '?') || ' to ' || coalesce(z.hp, '?') || ' (low ' || coalesce(r.hpmin, '?') || ')'
            || CASE WHEN r.died THEN '; died' ELSE '' END,
        '', NULL, NULL, CASE WHEN r.died THEN 'died' ELSE 'lived' END, NULL, NULL, r.hpmin, NULL, NULL, NULL
    FROM tl_ret r
    JOIN ep_sec a ON a.game_id = r.game_id AND a.pid = r.pid AND a.sec = r.t0
    JOIN ep_sec z ON z.game_id = r.game_id AND z.pid = r.pid AND z.sec = r.t1
),
tl_exchange AS (
    SELECT e.game_id, e.a, e.t0, e.t1, 'exchange',
        'on ' || coalesce(w.hero, e.b) || ', ' || e.a_secs || ' s of attacks, '
            || CASE WHEN e.b_secs > 0 THEN e.b_secs || ' s back' ELSE 'none back' END
            || '; hp ' || coalesce(a0.hp, '?') || ' to ' || coalesce(a1.hp, '?')
            || ', theirs ' || coalesce(b0.hp, '?') || ' to ' || coalesce(b1.hp, '?'),
        coalesce(w.hero, ''), NULL, e.b, CASE WHEN e.b_secs > 0 THEN 'answered' ELSE 'none_back' END, e.a_secs, e.b_secs, NULL,
        NULL, NULL, NULL
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
        coalesce(w.hero, '') || coalesce(',' || b.list, ''), NULL, k.tpid, CASE WHEN k.killed THEN 'killed' ELSE 'lived' END,
        NULL, NULL, k.hpmin, NULL, NULL, NULL
    FROM ep_kill k
    JOIN ep_who w ON w.game_id = k.game_id AND w.pid = k.tpid
    LEFT JOIN tl_by_kill b ON b.game_id = k.game_id AND b.team = k.team AND b.tpid = k.tpid AND b.t0 = k.t0
),
tl_job AS (
    SELECT game_id, pid, t0, t1, 'job',
        coalesce(job, src) || ': ' || CASE WHEN t1 IS NULL THEN 'no end logged' ELSE coalesce(why, 'ended') END, '', NULL,
        NULL, CASE WHEN t1 IS NULL THEN 'no_end' ELSE coalesce(why, 'ended') END, NULL, NULL, NULL,
        NULL, NULL, NULL
    FROM ep_job
),
tl_vis AS (
    SELECT v.*, EXISTS (SELECT 1 FROM ep_gap d WHERE d.game_id = v.game_id AND d.pid = v.pid AND d.dsec BETWEEN v.t1 - 1 AND v.t1 + 2) AS dead
    FROM ep_visit v
),
tl_visit AS (
    SELECT v.game_id, v.pid, v.t0, v.t1, 'visit',
        'in ' || v.lane || ', ends ' || CASE WHEN v.dead THEN 'dead' ELSE 'in ' || coalesce(s.mode, '?') END,
        '', v.lane, NULL, CASE WHEN v.dead THEN 'dead' ELSE s.mode END, NULL, NULL, NULL, NULL, NULL, NULL
    FROM tl_vis v LEFT JOIN ep_sec s ON s.game_id = v.game_id AND s.pid = v.pid AND s.sec = v.t1
),
-- A decision of ours: an `ev=choice` line of any kind but `shadow` and `decider` (per-second mode lines, not decisions). One
-- row per opportunity (hero, kind, lane, slot), from its last line unless a line started it; a line with no slot is its own.
tl_dec0 AS (
    SELECT c.game_id, c.seq, c.t, c.pid, c.kind AS what, c.want, c.go, c.why, c.src, c.lane, c.slot, c.aid,
        row_number() OVER (PARTITION BY c.game_id, c.pid, c.kind, c.lane, coalesce(c.slot, 'line ' || c.seq)
            ORDER BY coalesce(c.go, 0) = 1 DESC, c.t DESC, c.seq DESC) AS rn
    FROM gm CROSS JOIN ev_choice c ON c.game_id = gm.game_id
    WHERE c.kind NOT IN ('shadow', 'decider')
),
-- A started decision's trip: the hero's job with the same attempt id when both lines carry one, else (older logs, or a line
-- without one) that hero's first job of the decision's name to start within 1 s of the line. The id branch is bounded to 60 s
-- either side (a judgement, not measured): a restarted bot VM counts ids from 1 again, so one id can recur in a game.
tl_dec_job AS (
    SELECT d.game_id, d.seq, j.t0, j.t1, j.why,
        row_number() OVER (PARTITION BY d.game_id, d.seq ORDER BY j.t0) AS jn
    FROM tl_dec0 d
    JOIN ep_job j ON j.game_id = d.game_id AND j.pid = d.pid AND j.src = 'job' AND j.job = d.what AND (
        CASE WHEN d.aid IS NOT NULL AND j.aid IS NOT NULL THEN d.aid = j.aid AND j.t0 BETWEEN d.t - 60 AND d.t + 60 ELSE j.t0 BETWEEN d.t AND d.t + 1 END)
    WHERE d.rn = 1 AND d.go = 1
),
tl_dec AS (
    SELECT d.*, j.t0 AS jt0, j.t1 AS jt1, j.why AS jwhy,
        CASE
            WHEN coalesce(d.want, 0) = 0 THEN 'unwanted'
            WHEN d.src = 'shadow' THEN 'off'
            WHEN coalesce(d.go, 0) = 0 THEN 'refused'
            WHEN j.t0 IS NULL THEN 'no_start'
            WHEN j.t1 IS NULL THEN 'no_end'
            WHEN j.why = 'ok' THEN 'done'
            ELSE 'cut'
        END AS outcome
    FROM tl_dec0 d LEFT JOIN tl_dec_job j ON j.game_id = d.game_id AND j.seq = d.seq AND j.jn = 1
    WHERE d.rn = 1
),
tl_decision AS (
    SELECT game_id, pid, t, CASE WHEN outcome IN ('done', 'cut') THEN jt1 END, 'decision',
        what || ': ' || CASE outcome WHEN 'no_end' THEN 'started, no end logged' WHEN 'no_start' THEN 'go, no job start logged'
            ELSE outcome END
            || CASE WHEN outcome IN ('unwanted', 'refused', 'cut') THEN ' (' || coalesce(CASE WHEN outcome = 'cut' THEN jwhy ELSE why END, '?') || ')' ELSE '' END
            || coalesce(', slot ' || printf('%d:%02d', CAST(slot AS INTEGER) / 60, CAST(slot AS INTEGER) % 60), ''),
        '', CASE CAST(lane AS INTEGER) WHEN 1 THEN 'top' WHEN 2 THEN 'mid' WHEN 3 THEN 'bot' END,
        NULL, outcome, NULL, NULL, NULL,
        what, CASE outcome WHEN 'cut' THEN jwhy WHEN 'unwanted' THEN why WHEN 'refused' THEN why END, slot
    FROM tl_dec
),
tl_mode0 AS (
    SELECT s.game_id, s.pid, s.sec, s.mode, s.life,
        CASE WHEN s.mode = lag(s.mode) OVER w AND s.sec - lag(s.sec) OVER w <= 2 THEN 0 ELSE 1 END AS brk
    FROM ep_sec s WHERE s.live
    WINDOW w AS (PARTITION BY s.game_id, s.pid, s.life ORDER BY s.sec)
),
tl_mode AS (
    SELECT game_id, pid, min(sec), max(sec), 'mode', mode, '', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM (SELECT m.*, sum(brk) OVER (PARTITION BY game_id, pid, life ORDER BY sec) AS k FROM tl_mode0 m)
    GROUP BY game_id, pid, life, k HAVING max(sec) - min(sec) >= 2 AND mode <> 'retreat'
),
tl_cast AS (
    SELECT c.game_id, c.pid, c.t, NULL, 'cast', c.ab, '', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM gm CROSS JOIN ev_cast c ON c.game_id = gm.game_id WHERE c.ab IS NOT NULL
),
-- Lane creep deaths have one fate each (view creep_fate's rule, from unit_life's lane rows: fragment unit_life_lane, for the games read). A creep is a unit
-- with up to two rows: a hero's last hit (own_lh) and an enemy creep nobody got (other) from the log of the team that could have last-hit it (the creep_death line it
-- paired to), a deny (own_deny) on the hero who got it, and a creep of our own nobody got (lost) only when no enemy line of it exists (the unit has no cd_seq),
-- since then it is that log's own_lh or other row. enemy_deny is the denier's own_deny row seen from the other side: never a row.
cf_gm AS MATERIALIZED (SELECT game_id FROM gm WHERE :kind IS NULL OR instr(',' || :kind || ',', ',creep,') > 0),
ul_gm AS (SELECT game_id FROM cf_gm),
-- include: unit_life_in
-- include: unit_life_lane
-- include: unit_life_neutral
tl_fate AS MATERIALIZED (SELECT * FROM creep_fate_rows),
tl_pts AS (SELECT game_id AS kind, seq AS k, seq, t, x, y FROM tl_fate),
-- include: lane_label pts=tl_pts lab=tl_lab
tl_fate_lane AS (SELECT kind AS game_id, seq, lane FROM tl_lab),
-- `by` is a pid only on a creep a hero got.
tl_got AS (
    SELECT game_id, t, team, pid AS got, CASE fate WHEN 'own_lh' THEN 'last hit ' ELSE 'deny ' END || coalesce(kind, 'creep') AS detail,
        fate, kind
    FROM tl_fate WHERE fate IN ('own_lh', 'own_deny')
    UNION ALL
    SELECT n.game_id, n.t1, w.team, n.by_pid, 'last hit neutral', 'own_lh', 'neutral'
    FROM ul_nlife n JOIN ep_who w ON w.game_id = n.game_id AND w.pid = n.by_pid
    WHERE n.t1 IS NOT NULL AND n.by_pid IS NOT NULL
),
tl_creep AS (
    SELECT c.game_id, w.pid, c.t, NULL, 'creep', c.detail, '', NULL, NULL, c.fate, NULL, NULL, NULL, c.kind, NULL, NULL
    FROM tl_got c JOIN ep_who w ON w.game_id = c.game_id AND w.team = c.team AND CAST(c.got AS TEXT) = CAST(w.pid AS TEXT)
),
-- Creeps nobody got: no hero, so a team of their own (the logging team) and the lane of the death's place (fragment lane_label).
-- why, for other: tower (tw = 1: one of the logging team's towers hit it the frame before; under it, not surely killed by it),
-- open (tw = 0), NULL (a build before the field); as view lane_waste's place.
tl_nobody AS (
    SELECT f.game_id, NULL AS pid, f.t, NULL AS t1, 'creep' AS kind,
        CASE f.fate WHEN 'other' THEN 'enemy ' || coalesce(f.kind, 'creep') || ': nobody got it'
                || CASE WHEN f.tw = 1 THEN ', under our tower' ELSE '' END
            ELSE 'our ' || coalesce(f.kind, 'creep') || ': lost, no enemy hero logged it' END AS detail,
        '' AS others, coalesce(l.lane, 'other') AS in_lane, NULL AS other_pid, f.fate AS outcome, NULL AS a_secs, NULL AS b_secs,
        NULL AS hpmin, f.kind AS what,
        CASE WHEN f.fate = 'other' THEN CASE f.tw WHEN 1 THEN 'tower' WHEN 0 THEN 'open' END END AS why, NULL AS slot, f.team
    FROM tl_fate f
    LEFT JOIN tl_fate_lane l ON l.game_id = f.game_id AND l.seq = f.seq
    WHERE (f.side = 'enemy' AND f.fate = 'other')
        OR (f.side = 'own' AND f.fate = 'lost' AND NOT EXISTS (
            SELECT 1 FROM ul_lall e WHERE e.game_id = f.game_id AND e.seq = f.seq AND e.cd_seq IS NOT NULL))
),
tl_state AS (
    SELECT s.game_id, s.pid, s.sec, NULL, 'state',
        'hp ' || coalesce(s.hp, '?') || ', ' || coalesce(s.mode, '?') || ', enemy '
            || coalesce(CAST(round(sqrt(min(CASE WHEN o.team <> s.team
                THEN (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) END))) AS INTEGER), '?')
            || ', allies '
            || coalesce(sum(o.team = s.team AND (o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y) <= 1200 * 1200), 0),
        '', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
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
    UNION ALL SELECT * FROM tl_decision
    UNION ALL SELECT * FROM tl_mode
    UNION ALL SELECT * FROM tl_cast
    UNION ALL SELECT * FROM tl_creep
    UNION ALL SELECT * FROM tl_state
),
tl_in AS MATERIALIZED (
    SELECT a.*, w.team, w.pos, w.hero, CAST(round(a.t) AS INTEGER) AS sec
    FROM tl_all a JOIN ep_who w ON w.game_id = a.game_id AND w.pid = a.pid
    WHERE CASE WHEN a.kind = 'death' THEN floor(a.t) ELSE a.t END <= coalesce(:to, 1e9) AND coalesce(a.t1, a.t) >= coalesce(:from, -1e9)
        AND (:kind IS NULL OR instr(',' || :kind || ',', ',' || a.kind || ',') > 0)
        AND (:pid IS NULL OR a.pid = :pid OR a.other_pid = :pid
            OR instr(',' || a.others || ',', ',' || (SELECT w2.hero FROM ep_who w2 WHERE w2.game_id = a.game_id AND w2.pid = :pid) || ',') > 0)
        AND (:hero IS NULL OR w.hero = :hero OR instr(',' || a.others || ',', ',' || :hero || ',') > 0)
    UNION ALL
    -- A row with no hero is no hero's: --hero and --pid leave it out.
    SELECT n.game_id, n.pid, n.t, n.t1, n.kind, n.detail, n.others, n.in_lane, n.other_pid, n.outcome, n.a_secs, n.b_secs,
        n.hpmin, n.what, n.why, n.slot, n.team, NULL, NULL, CAST(round(n.t) AS INTEGER)
    FROM tl_nobody n
    WHERE n.t <= coalesce(:to, 1e9) AND n.t >= coalesce(:from, -1e9) AND :pid IS NULL AND :hero IS NULL
        AND (:kind IS NULL OR instr(',' || :kind || ',', ',creep,') > 0)
),
-- A moment a half second past the last live one (a death, a cast) takes the second before's place.
tl_row AS (
    SELECT i.*, coalesce(i.in_lane, p.lane, p1.lane, 'other') AS lane
    FROM tl_in i
    LEFT JOIN ep_place p ON p.game_id = i.game_id AND p.pid = i.pid AND p.sec = i.sec
    LEFT JOIN ep_place p1 ON p1.game_id = i.game_id AND p1.pid = i.pid AND p1.sec = i.sec - 1
),
tl_sel AS MATERIALIZED (
    SELECT *, CAST(round(t1) AS INTEGER) AS sec1,
        kind IN ('death', 'retreat', 'exchange', 'kill_try', 'job', 'visit') AS epi
    FROM tl_row WHERE :lane IS NULL OR lane = :lane
),
-- Distance to the nearest live enemy hero, at the seconds an episode starts and ends.
tl_at AS (
    SELECT DISTINCT game_id, pid, sec FROM tl_sel WHERE epi
    UNION SELECT game_id, pid, sec1 FROM tl_sel WHERE epi AND sec1 IS NOT NULL
),
tl_near AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.sec,
        CAST(round(sqrt(min((o.x - s.x) * (o.x - s.x) + (o.y - s.y) * (o.y - s.y)))) AS INTEGER) AS d
    FROM tl_at a
    JOIN ep_sec s ON s.game_id = a.game_id AND s.pid = a.pid AND s.sec = a.sec
    JOIN ep_sec o ON o.game_id = a.game_id AND o.sec = a.sec AND o.team <> s.team AND o.live
    GROUP BY a.game_id, a.pid, a.sec
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
    UNION ALL
    SELECT g.game_id, t.team, 'decision', t.name || ': no decisions in the log'
    FROM gm g, tl_team t
    WHERE NOT EXISTS (SELECT 1 FROM ev_choice c JOIN ep_who w ON w.game_id = c.game_id AND w.pid = c.pid
        WHERE c.game_id = g.game_id AND w.team = t.team AND c.kind NOT IN ('shadow', 'decider'))
),
tl_kinds (kind) AS (VALUES ('death'), ('retreat'), ('exchange'), ('kill_try'), ('visit'), ('mode'), ('state'), ('cast'), ('creep'),
    ('decision')),
timeline_rows AS (
SELECT gm.file, gm.game, o.t, o.t1, o.lane, o.team, o.pos, o.pid, o.hero, o.kind, o.detail, o.who,
    o.secs, o.other_pid, o.other, o.a_secs, o.b_secs, o.hp0, o.hp1, o.ohp0, o.ohp1, o.hpmin, o.outcome, o.d0, o.d1,
    gm.batch, gm.lineup, gm.arm, gm.seat, gm.rep,
    CASE WHEN gm.seat_team IS NULL THEN NULL WHEN o.team = gm.seat_team THEN 'test' WHEN o.team IS NOT NULL THEN 'opp' END AS side,
    o.what, o.why, o.slot
FROM (
    SELECT r.game_id, round(r.t, 1) AS t, round(r.t1, 1) AS t1, r.lane, r.team, r.pos, r.pid, r.hero, r.kind, r.detail,
        ',' || r.hero || ',' || CASE WHEN r.others = '' THEN '' ELSE r.others || ',' END AS who,
        r.sec1 - r.sec AS secs, r.other_pid, ow.hero AS other, r.a_secs, r.b_secs,
        h0.hp AS hp0, h1.hp AS hp1, o0.hp AS ohp0, o1.hp AS ohp1, r.hpmin, r.outcome, n0.d AS d0, n1.d AS d1,
        r.what, r.why, r.slot
    FROM tl_sel r
    LEFT JOIN ep_who ow ON ow.game_id = r.game_id AND ow.pid = r.other_pid
    LEFT JOIN ep_sec h0 ON r.epi AND h0.game_id = r.game_id AND h0.pid = r.pid AND h0.sec = r.sec
    LEFT JOIN ep_sec h1 ON r.epi AND h1.game_id = r.game_id AND h1.pid = r.pid AND h1.sec = r.sec1
    LEFT JOIN ep_sec o0 ON r.epi AND o0.game_id = r.game_id AND o0.pid = r.other_pid AND o0.sec = r.sec
    LEFT JOIN ep_sec o1 ON r.epi AND o1.game_id = r.game_id AND o1.pid = r.other_pid AND o1.sec = r.sec1
    LEFT JOIN tl_near n0 ON r.epi AND n0.game_id = r.game_id AND n0.pid = r.pid AND n0.sec = r.sec
    LEFT JOIN tl_near n1 ON r.epi AND n1.game_id = r.game_id AND n1.pid = r.pid AND n1.sec = r.sec1
    UNION ALL
    SELECT game_id, NULL, NULL, NULL, team, NULL, NULL, NULL, 'not_logged', detail, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM tl_lack l
    WHERE :kind IS NULL OR EXISTS (
        SELECT 1 FROM tl_kinds k
        WHERE instr(',' || l.kinds || ',', ',' || k.kind || ',') > 0 AND instr(',' || :kind || ',', ',' || k.kind || ',') > 0)
) o JOIN gm ON gm.game_id = o.game_id
),
