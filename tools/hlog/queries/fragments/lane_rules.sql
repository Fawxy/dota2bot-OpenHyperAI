-- Fragment (`-- include: lane_rules`): the doctrine's violations for D1, D2, D3, D7 and D9 (docs/team/DOCTRINE.md), found from
-- what happened (every hero's own ev=snap: position, HP, the `hit` flag, mode, level, lane distance; deaths), never from our
-- threat read, so it runs on games from before the rules were built. The including query defines `gm(game_id, file)` first.
-- Params: until (default 720, the head-to-head's 12:00). Ends with a comma. Final CTE:
--   lr_case(rule, game_id, pid, team, pos, side, t, viol, cause, hp, en, al, secs, mode)
--   side `ours` when the hero's last ev=bot line has any Ours switch on (`ours` field with a `:1`), else `oha`.
-- Each second of each hero is its latest snapshot in that whole second, alive with HP above 0. Reach (`judgement`): an enemy
-- can reach me within its attack range + 600 (about 2 s of walking); allies and enemies "near" within 1,200; an enemy tower's
-- reach 750 (lane_spot TOWER_RING).
-- D1 situation: 2 or more enemies in reach, more than me and the allies near, and I am hit by a hero or at 50% HP or less;
--    one case per onset (no such second in the 5 before). viol when I died within 10 s (cause died) or 3 s later the
--    situation still holds, the nearest enemy is not 150 farther and no own tower is within 800 (stayed); else left.
-- D2: a second in mode retreat at 80% HP or more with no enemy hero within 1,500, outside 1,500 of our fountain; one case per
--    onset (5 s gap), secs = such seconds in the 30 s from it, 2 or more (a 1 s flicker is no retreat). Every case is a violation (cause oha_retreat or ours_retreat
--    by side: the mode name does not tell whose code ran).
-- D3: each retreat-mode run (gaps of 3 s or less, 2 s or more long). viol tower: it entered an enemy tower's reach it did not
--    start in; viol no_stop: 10 s or more of it at 50% HP or more after the last second with an enemy within 1,500 (the
--    whole run when none came near; `fountain` when it ended within 1,500 of our fountain). Not measured: walking through the
--    enemy wave (no per-second creep positions for the other team in fog-free form here).
-- D7: per lane pair (pos 5 with pos 1, pos 4 with pos 3), 1:30 to 10:00: a departure is the first second the support is more
--    than 2,000 from its core after being within 1,200 of it in the 15 s before. The core needs it when, at any second from
--    that last together second to the departure, the core is at 40% HP or less, or 2 or more enemies are within 1,200 of it
--    while it is at 70% HP or less or hit by a hero (the 1v2 with a kill threat; two enemy laners near is every 2v2 lane
--    second, so alone it is no need), or an enemy within 1,500 of it is 2 levels above it or has 6 while it has not.
--    viol: a departure while needed.
-- D9: each run of seconds (gaps of 3 s or less) a hero spends more than 1,200 from every lane path (`ld`), outside 2,500 of
--    its fountain, from 0:30. viol: some second of it with 2 or more enemies in reach and no ally near (cause died when the
--    hero died in it or within 2 s after).
-- ensure: ev_snap(pid, x, y, alive, hp, hit, mode, lvl, ar, ld, deaths)
-- ensure: ev_bot(pid, team, pos, ours)
lr_who AS MATERIALIZED (
    SELECT game_id, pid, team, pos, CASE WHEN instr(coalesce(ours, ''), ':1') > 0 THEN 'ours' ELSE 'oha' END AS side
    FROM (
        SELECT b.game_id, b.pid, b.team, b.pos, b.ours, row_number() OVER (PARTITION BY b.game_id, b.pid ORDER BY b.seq DESC) AS rn
        FROM ev_bot b JOIN gm ON gm.game_id = b.game_id WHERE b.team IS NOT NULL AND b.pos IS NOT NULL
    ) WHERE rn = 1
),
lr_s0 AS MATERIALIZED (
    SELECT s.game_id, s.pid, w.team, w.pos, w.side, CAST(round(s.t) AS INTEGER) AS sec, max(s.seq) AS seq, s.x, s.y, s.hp,
        coalesce(s.hit, 0) AS hit, s.mode, s.lvl, coalesce(s.ar, 550) AS ar, s.ld, s.deaths,
        CASE w.team WHEN 2 THEN (s.x + 6700) * (s.x + 6700) + (s.y + 6700) * (s.y + 6700)
                    ELSE (s.x - 6928) * (s.x - 6928) + (s.y - 6372) * (s.y - 6372) END AS fnt2
    FROM ev_snap s JOIN lr_who w ON w.game_id = s.game_id AND w.pid = s.pid
    WHERE s.t >= 0 AND s.t <= coalesce(:until, 720) + 15 AND s.alive IS NOT 0 AND s.hp > 0 AND typeof(s.x) IN ('integer', 'real')
    GROUP BY s.game_id, s.pid, CAST(round(s.t) AS INTEGER)
),
lr_s1 AS MATERIALIZED (
    SELECT lr_s0.*, lag(x) OVER w AS px, lag(y) OVER w AS py, lag(sec) OVER w AS psec, lead(sec) OVER w AS nsec, lead(deaths) OVER w AS nd
    FROM lr_s0 WINDOW w AS (PARTITION BY game_id, pid ORDER BY sec)
),
-- A death: the deaths counter rises after a gap of more than 3 s (bots log nothing while dead). A killed hero can first log a
-- few snapshots at its fountain with HP rising from 0; that jump (more than 1,500 in 3 s or less, landing within 1,500 of the
-- fountain, up to 8 s before the gap) dates the death at the second before it, and those fountain seconds are dropped.
lr_end AS (SELECT game_id, pid, sec AS esec FROM lr_s1 WHERE nd > deaths AND nsec - sec > 3),
lr_jump AS (
    SELECT game_id, pid, sec AS jsec, psec FROM lr_s1
    WHERE psec IS NOT NULL AND sec - psec <= 3 AND (x - px) * (x - px) + (y - py) * (y - py) > 1500 * 1500 AND fnt2 <= 1500 * 1500
),
lr_death AS MATERIALIZED (
    SELECT e.game_id, e.pid, e.esec,
        coalesce((SELECT max(j.psec) FROM lr_jump j WHERE j.game_id = e.game_id AND j.pid = e.pid AND j.jsec <= e.esec AND j.jsec >= e.esec - 8), e.esec) AS dsec
    FROM lr_end e
),
lr_s AS MATERIALIZED (
    SELECT s.* FROM lr_s1 s
    WHERE NOT EXISTS (SELECT 1 FROM lr_death d WHERE d.game_id = s.game_id AND d.pid = s.pid AND s.sec > d.dsec AND s.sec <= d.esec)
),
lr_p AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.sec,
        coalesce(sum(b.team <> a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= (b.ar + 600) * (b.ar + 600)), 0) AS en_r,
        coalesce(sum(b.team <> a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= 1200 * 1200), 0) AS en12,
        coalesce(sum(b.team = a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= 1200 * 1200), 0) AS al12,
        sqrt(min(CASE WHEN b.team <> a.team THEN (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) END)) AS en_d
    FROM lr_s a LEFT JOIN lr_s b ON b.game_id = a.game_id AND b.sec = a.sec AND b.pid <> a.pid
    GROUP BY a.game_id, a.pid, a.sec
),
-- Tower positions (team, x, y): dynamic.js TOWERS, kept equal by a test (as fragment core_death's `tw`).
lr_tw (team, x, y) AS (VALUES
    (2, -3952, -6112), (2, -4640, -4144), (2, -6592, -3408), (2, -360, -6256), (2, 4860, -6379), (2, -3190, -2926),
    (2, -6501, -872), (2, -6336, 1856), (2, -5712, -4864), (2, -5392, -5192), (2, -1544, -1408),
    (3, 4944, 4776), (3, -128, 6016), (3, -5275, 6036), (3, 2496, 2112), (3, 524, 652), (3, 6400, 384), (3, 6336, 3032),
    (3, 3552, 5776), (3, 4272, 3759), (3, 5280, 4432), (3, 6269, -2240)),
lr_f AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.team, a.pos, a.side, a.sec, a.x, a.y, a.hp, a.hit, a.mode, a.lvl, a.ld, a.fnt2,
        p.en_r, p.en12, p.al12, coalesce(p.en_d, 99999) AS en_d,
        (SELECT min((t.x - a.x) * (t.x - a.x) + (t.y - a.y) * (t.y - a.y)) FROM lr_tw t WHERE t.team = a.team) AS own_tw2,
        (SELECT min((t.x - a.x) * (t.x - a.x) + (t.y - a.y) * (t.y - a.y)) FROM lr_tw t WHERE t.team <> a.team) AS en_tw2
    FROM lr_s a JOIN lr_p p ON p.game_id = a.game_id AND p.pid = a.pid AND p.sec = a.sec
),
lr_d1s AS (
    SELECT f.*, lag(f.sec) OVER (PARTITION BY f.game_id, f.pid ORDER BY f.sec) AS prev FROM lr_f f
    WHERE f.en_r >= 2 AND f.en_r > f.al12 + 1 AND (f.hit > 0 OR f.hp <= 50)
),
lr_d1 AS (
    SELECT o.game_id, o.pid, o.team, o.pos, o.side, o.sec AS t, o.hp, o.en_r AS en, o.al12 AS al, o.mode, o.en_d AS d0,
        a.sec AS a_sec, a.en_r AS en3, a.al12 AS al3, a.en_d AS d3, a.own_tw2 AS tw3,
        (SELECT min(d.dsec) FROM lr_death d WHERE d.game_id = o.game_id AND d.pid = o.pid AND d.dsec >= o.sec AND d.dsec <= o.sec + 10) AS died
    FROM lr_d1s o LEFT JOIN lr_f a ON a.game_id = o.game_id AND a.pid = o.pid AND a.sec = o.sec + 3
    WHERE (o.prev IS NULL OR o.sec - o.prev > 5) AND o.sec <= coalesce(:until, 720)
),
lr_d2s AS (
    SELECT f.*, lag(f.sec) OVER (PARTITION BY f.game_id, f.pid ORDER BY f.sec) AS prev FROM lr_f f
    WHERE f.mode = 'retreat' AND f.hp >= 80 AND f.en_d > 1500 AND f.fnt2 > 1500 * 1500
),
lr_d2 AS (
    SELECT o.game_id, o.pid, o.team, o.pos, o.side, o.sec AS t, o.hp, o.mode,
        (SELECT count(*) FROM lr_d2s z WHERE z.game_id = o.game_id AND z.pid = o.pid AND z.sec >= o.sec AND z.sec < o.sec + 30) AS secs
    FROM lr_d2s o WHERE (o.prev IS NULL OR o.sec - o.prev > 5) AND o.sec <= coalesce(:until, 720)
),
lr_d2v AS (SELECT * FROM lr_d2 WHERE secs >= 2),
lr_r0 AS (
    SELECT f.*, CASE WHEN lag(f.sec) OVER w IS NULL OR f.sec - lag(f.sec) OVER w > 3 THEN 1 ELSE 0 END AS nw
    FROM lr_f f WHERE f.mode = 'retreat' WINDOW w AS (PARTITION BY f.game_id, f.pid ORDER BY f.sec)
),
lr_r1 AS (SELECT r.*, sum(r.nw) OVER (PARTITION BY r.game_id, r.pid ORDER BY r.sec) AS ep FROM lr_r0 r),
lr_r2 AS (
    SELECT r.*, max(CASE WHEN r.en_d <= 1500 THEN r.sec END) OVER e AS last_thr,
        first_value(r.en_tw2) OVER (PARTITION BY r.game_id, r.pid, r.ep ORDER BY r.sec) AS tw0,
        first_value(r.hp) OVER (PARTITION BY r.game_id, r.pid, r.ep ORDER BY r.sec) AS hp0
    FROM lr_r1 r WINDOW e AS (PARTITION BY r.game_id, r.pid, r.ep)
),
lr_d3e AS (
    SELECT game_id, pid, team, pos, side, ep, min(sec) AS t, max(sec) - min(sec) + 1 AS span, max(hp0) AS hp,
        max(tw0) <= 750 * 750 AS start_tower, sum(en_tw2 <= 750 * 750) AS tower_s,
        sum(sec > coalesce(last_thr, -1) AND hp >= 50) AS tail_s, max(fnt2 <= 1500 * 1500) AS fountain
    FROM lr_r2 GROUP BY game_id, pid, ep
),
lr_d3 AS (
    SELECT e.*, CASE WHEN NOT e.start_tower AND e.tower_s > 0 THEN 'tower'
                     WHEN e.tail_s >= 10 THEN CASE WHEN e.fountain THEN 'fountain' ELSE 'no_stop' END END AS why
    FROM lr_d3e e WHERE e.span >= 2 AND e.t <= coalesce(:until, 720)
),
lr_pair AS (
    SELECT s.game_id, s.team, s.side, s.pid AS sup, s.pos AS spos, c.pid AS core
    FROM lr_who s JOIN lr_who c ON c.game_id = s.game_id AND c.team = s.team AND ((s.pos = 5 AND c.pos = 1) OR (s.pos = 4 AND c.pos = 3))
),
lr_ps AS MATERIALIZED (
    SELECT p.game_id, p.team, p.side, p.sup, p.spos, a.sec, a.mode AS smode, c.hp AS chp, c.en12 AS cen,
        (a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y) <= 1200 * 1200 AS tog,
        (a.x - c.x) * (a.x - c.x) + (a.y - c.y) * (a.y - c.y) > 2000 * 2000 AS apart,
        c.hp <= 40 OR (c.en12 >= 2 AND (c.hp <= 70 OR c.hit > 0)) OR EXISTS (SELECT 1 FROM lr_f e WHERE e.game_id = c.game_id AND e.sec = c.sec AND e.team <> c.team
            AND (e.x - c.x) * (e.x - c.x) + (e.y - c.y) * (e.y - c.y) <= 1500 * 1500
            AND (e.lvl >= c.lvl + 2 OR (e.lvl >= 6 AND c.lvl < 6))) AS need
    FROM lr_pair p JOIN lr_f a ON a.game_id = p.game_id AND a.pid = p.sup
    JOIN lr_f c ON c.game_id = p.game_id AND c.pid = p.core AND c.sec = a.sec
    WHERE a.sec >= 90 AND a.sec <= min(coalesce(:until, 720), 600)
),
lr_pw AS (
    SELECT q.*, lag(q.apart) OVER w AS prev_apart, max(CASE WHEN q.tog THEN q.sec END) OVER (w ROWS UNBOUNDED PRECEDING) AS last_tog
    FROM lr_ps q WINDOW w AS (PARTITION BY q.game_id, q.sup ORDER BY q.sec)
),
lr_d7 AS (
    SELECT d.game_id, d.sup AS pid, d.team, d.spos AS pos, d.side, d.sec AS t, d.smode AS mode, d.chp AS hp, d.cen AS en,
        EXISTS (SELECT 1 FROM lr_ps n WHERE n.game_id = d.game_id AND n.sup = d.sup AND n.sec >= d.last_tog AND n.sec <= d.sec AND n.need) AS needed
    FROM lr_pw d WHERE d.apart AND NOT coalesce(d.prev_apart, 0) AND d.last_tog >= d.sec - 15
),
lr_t0 AS (
    SELECT f.*, CASE WHEN lag(f.sec) OVER w IS NULL OR f.sec - lag(f.sec) OVER w > 3 THEN 1 ELSE 0 END AS nw
    FROM lr_f f WHERE f.ld > 1200 AND f.fnt2 > 2500 * 2500 AND f.sec >= 30
    WINDOW w AS (PARTITION BY f.game_id, f.pid ORDER BY f.sec)
),
lr_t1 AS (SELECT r.*, sum(r.nw) OVER (PARTITION BY r.game_id, r.pid ORDER BY r.sec) AS ep FROM lr_t0 r),
lr_d9e AS (
    SELECT game_id, pid, team, pos, side, ep, min(sec) AS t, max(sec) AS t1, count(*) AS secs,
        sum(en_r >= 2 AND al12 = 0) AS exposed, max(CASE WHEN en_r >= 2 AND al12 = 0 THEN en_r END) AS en, min(hp) AS hp,
        (SELECT r.mode FROM lr_t1 r WHERE r.game_id = x.game_id AND r.pid = x.pid AND r.ep = x.ep ORDER BY r.sec LIMIT 1) AS mode
    FROM lr_t1 x GROUP BY game_id, pid, ep
),
lr_d9 AS (
    SELECT e.*, EXISTS (SELECT 1 FROM lr_death d WHERE d.game_id = e.game_id AND d.pid = e.pid AND d.dsec >= e.t AND d.dsec <= e.t1 + 2) AS died
    FROM lr_d9e e WHERE e.t <= coalesce(:until, 720)
),
lr_case AS (
    SELECT 'D1' AS rule, game_id, pid, team, pos, side, t, died IS NOT NULL OR (a_sec IS NOT NULL AND en3 >= 2 AND en3 > al3 + 1
            AND d3 <= d0 + 150 AND coalesce(tw3, 1e12) > 800 * 800) AS viol,
        CASE WHEN died IS NOT NULL THEN 'died' WHEN a_sec IS NULL THEN 'unseen'
             WHEN en3 >= 2 AND en3 > al3 + 1 AND d3 <= d0 + 150 AND coalesce(tw3, 1e12) > 800 * 800 THEN 'stayed' ELSE 'left' END AS cause,
        hp, en, al, NULL AS secs, mode
    FROM lr_d1
    UNION ALL
    SELECT 'D2', game_id, pid, team, pos, side, t, 1, side || '_retreat', hp, 0, NULL, secs, mode FROM lr_d2v
    UNION ALL
    SELECT 'D3', game_id, pid, team, pos, side, t, why IS NOT NULL, coalesce(why, 'ok'), hp, NULL, NULL, span, 'retreat' FROM lr_d3
    UNION ALL
    SELECT 'D7', game_id, pid, team, pos, side, t, needed, CASE WHEN needed THEN 'needed' ELSE 'free' END, hp, en, NULL, NULL, mode FROM lr_d7
    UNION ALL
    SELECT 'D9', game_id, pid, team, pos, side, t, exposed > 0, CASE WHEN exposed = 0 THEN 'safe' WHEN died THEN 'died' ELSE 'exposed' END,
        hp, en, 0, secs, mode
    FROM lr_d9
),
