-- Fragment (`-- include: lane_rules`): the doctrine's violations for D1, D2, D3, D7, D9, D24 and D24h (docs/team/DOCTRINE.md), found from
-- what happened (every hero's own ev=snap: position, HP, the `hit` flag, mode, level, lane distance; deaths), never from our
-- threat read, so it runs on games from before the rules were built. The including query defines `gm(game_id, file)` first.
-- Params: until (default 720, the head-to-head's 12:00). Ends with a comma. Final CTEs:
--   lr_case(rule, game_id, pid, team, pos, side, t, viol, cause, hp, en, al, secs, mode);  lr_death(game_id, pid, esec, dsec)
--   side `ours` when the hero's last ev=bot line has any Ours switch on (`ours` field with a `:1`), else `oha`.
-- Each second of each hero is its latest snapshot in that whole second, alive with HP above 0. Reach (`judgement`): an enemy
-- can reach me within its attack range + 600 (about 2 s of walking); allies and enemies "near" within 1,200; an enemy tower's
-- reach 750 (lane_spot TOWER_RING). Towers come from a fixed table, so a destroyed tower still counts (rare before 12:00).
-- D1 situation: 2 or more enemies in reach, more than me and the allies near, and I am hit by a hero or at 50% HP or less;
--    one case per onset (no such second in the 5 before). Cause, first match: died (within 10 s), unseen (no snapshot 3 s
--    later), left (3 s later I am 300 or more farther from where the enemies in reach stood at the onset, or within 800 of
--    an own tower or 1,500 of our fountain: my own movement, so a chaser keeping up does not make it a stay), stayed (the
--    situation still holds), ended. viol: died or stayed.
-- D2: a second in mode retreat at 80% HP or more with no enemy hero within 1,500, outside 1,500 of our fountain; one case per
--    onset (5 s gap), secs = such seconds in the 30 s from it, 2 or more (a 1 s flicker is no retreat). Every case is a
--    violation (cause oha_retreat or ours_retreat by side: the mode name does not tell whose code ran).
-- D3: each retreat-mode run (gaps of 3 s or less, 2 s or more long). viol tower: it entered an enemy tower's reach it did not
--    start in; viol no_stop: 10 s or more of it at 50% HP or more after the last second with an enemy within 1,500 (the
--    whole run when none came near; `fountain` when it reached 1,500 of our fountain). A tail second counts only while our
--    own lane's front (ev=front, its latest line; the lane from team and pos as GetAssignedLane gives it) is nearer than our
--    fountain: walking on to a nearer fountain is right (user 11/11/2026); a log with no ev=front line counts every one.
--    Not measured: walking through the enemy wave (no per-second creep positions for the other team here).
-- D7: per lane pair (pos 5 with pos 1, pos 4 with pos 3), 1:30 to 10:00: a departure is a second the support is more than
--    2,000 from its core, the second before (a snapshot one second earlier) it was not, and it was within 1,200 of the core
--    in the 15 s before; one departure per together spell (a dip back under 2,000 is the same departure). The core needs
--    it when, at any second from that last together second to the departure, the core is at 40% HP or less, or 2 or more
--    enemies are within 1,200 of it while it is at 70% HP or less or hit by a hero (the 1v2 with a kill threat; two enemy
--    laners near is every 2v2 lane second, so alone it is no need), or an enemy within 1,500 of it is 2 levels above it or
--    has 6 while it has not. Cause: self (the support was in retreat mode: staying alive is the higher group; at any HP, so a
--    needless high-HP retreat away from the core is D2's count, not D7's), needed, free.
--    viol: needed.
-- D9: a trip is a run of seconds (gaps of 3 s or less, 3 s or more long) more than 1,200 from every lane path (`ld`),
--    outside 2,500 of the fountain, from 0:30, that starts from lane (the snapshot before, 3 s or less earlier, within 1,200
--    of a lane path) and not in retreat mode (a flight is D1's). viol: some second of it with 2 or more enemies in reach and
--    no ally near (cause died when the hero died in it or within 2 s after, else exposed).
-- D24 (the leave half): a retreat-mode onset (in retreat this second, not in the 3 s before) from 1:30 with an enemy hero in
--    reach that does not outnumber us (enemies in reach no more than me and the allies near), at 50% HP or more (`judgement`:
--    the snapshot has no burst, so HP stands in for "not in danger of dying"), outside an enemy tower's reach and 1,500 of our
--    fountain. viol: every enemy in reach stands within creep aggro (500) of our lane front, the nearest of the three
--    (ev=front, its latest line): D24 stays while they pay in creep damage (EC-102); one outside it hits for free, and
--    stepping out is right (cause free_hit). Else cause oha_retreat or ours_retreat by side. The front is the wave's lead
--    creep, so an enemy beside the back of our wave reads free (`judgement`: under-counts, the same for both sides).
--    A log with no ev=front line before the onset reads every case free_hit (no violations).
-- D24h (the hit-back half, slice hit-back): a second from 1:30 in which I am hit by a hero (`hit`), at 50% HP or more, not in
--    retreat mode, outside an enemy tower's reach, not outnumbered (as D24), with an enemy hero in reach standing within creep
--    aggro (500) of our lane front (as D24's test); one case per onset (no such second in the 5 before). Cause, first match:
--    hit_back (in that second or the 3 after, my snapshot's attack target `tgt` is an enemy hero), left (retreat mode in them),
--    died (within 5 s), none. viol: every cause but hit_back. A leave counts: the hitter is paying our creeps and we are in
--    no danger, so leaving gives the exchange away as standing does (on h2hskill1 the sides left the same share unanswered
--    and differed only in leaves and hits back, so the count without leaves hid the difference). The snapshot does not say
--    which hero hit me, so a hit back on another enemy hero counts (`judgement`).
-- ensure: ev_snap(pid, x, y, alive, hp, hit, mode, lvl, ar, ld, deaths, tgt)
-- ensure: ev_bot(pid, team, pos, ours, hero)
-- ensure: ev_front(team, topx, topy, midx, midy, botx, boty)
lr_who AS MATERIALIZED (
    SELECT game_id, pid, team, pos, CASE WHEN instr(coalesce(ours, ''), ':1') > 0 THEN 'ours' ELSE 'oha' END AS side
    FROM (
        SELECT b.game_id, b.pid, b.team, b.pos, b.ours, row_number() OVER (PARTITION BY b.game_id, b.pid ORDER BY b.seq DESC) AS rn
        FROM ev_bot b JOIN gm ON gm.game_id = b.game_id WHERE b.team IS NOT NULL AND b.pos IS NOT NULL
    ) WHERE rn = 1
),
-- Every snapshot second, HP 0 ones too (a killed hero logs a few where it fell), for dating deaths.
lr_s0 AS MATERIALIZED (
    SELECT s.game_id, s.pid, w.team, w.pos, w.side, CAST(round(s.t) AS INTEGER) AS sec, max(s.seq) AS seq, s.x, s.y, s.hp,
        coalesce(s.hit, 0) AS hit, s.mode, s.lvl, coalesce(s.ar, 550) AS ar, s.ld, s.deaths, s.tgt,
        CASE w.team WHEN 2 THEN (s.x + 6700) * (s.x + 6700) + (s.y + 6700) * (s.y + 6700)
                    ELSE (s.x - 6928) * (s.x - 6928) + (s.y - 6372) * (s.y - 6372) END AS fnt2
    FROM ev_snap s JOIN lr_who w ON w.game_id = s.game_id AND w.pid = s.pid
    WHERE s.t >= 0 AND s.t <= coalesce(:until, 720) + 15 AND s.alive IS NOT 0 AND typeof(s.x) IN ('integer', 'real')
    GROUP BY s.game_id, s.pid, CAST(round(s.t) AS INTEGER)
),
lr_gl AS MATERIALIZED (SELECT game_id, max(sec) AS gl FROM lr_s0 GROUP BY game_id),
lr_s1 AS MATERIALIZED (
    SELECT lr_s0.*, lag(x) OVER w AS px, lag(y) OVER w AS py, lag(sec) OVER w AS psec, lead(sec) OVER w AS nsec, lead(deaths) OVER w AS nd
    FROM lr_s0 WINDOW w AS (PARTITION BY game_id, pid ORDER BY sec)
),
-- A death ends a hero's snapshots for more than 3 s (bots log nothing while dead): its deaths counter is higher after the
-- gap, or the gap runs to the game's last snapshot (hero_death's `lastsnap`). A killed hero can log snapshots at its fountain
-- with HP rising from 0 before the gap; a jump there (more than 1,500 in 3 s or less, landing within 1,500 of the fountain,
-- up to 8 s before the gap) cuts them off. The death is dated at the last snapshot with HP above 0 before the cut, and the
-- seconds from it to the gap are dropped.
lr_end AS (
    SELECT s.game_id, s.pid, s.sec AS esec FROM lr_s1 s JOIN lr_gl g ON g.game_id = s.game_id
    WHERE (s.nd > s.deaths AND s.nsec - s.sec > 3) OR (s.nsec IS NULL AND g.gl - s.sec > 3)
),
lr_jump AS (
    SELECT game_id, pid, sec AS jsec FROM lr_s1
    WHERE psec IS NOT NULL AND sec - psec <= 3 AND (x - px) * (x - px) + (y - py) * (y - py) > 1500 * 1500 AND fnt2 <= 1500 * 1500
),
lr_cut AS (
    SELECT e.game_id, e.pid, e.esec,
        coalesce((SELECT min(j.jsec) FROM lr_jump j WHERE j.game_id = e.game_id AND j.pid = e.pid AND j.jsec <= e.esec AND j.jsec >= e.esec - 8), e.esec + 1) AS cut
    FROM lr_end e
),
lr_death AS MATERIALIZED (
    SELECT c.game_id, c.pid, c.esec,
        coalesce((SELECT max(s.sec) FROM lr_s0 s WHERE s.game_id = c.game_id AND s.pid = c.pid AND s.hp > 0 AND s.sec < c.cut AND s.sec >= c.esec - 20), c.esec) AS dsec
    FROM lr_cut c
),
lr_s AS MATERIALIZED (
    SELECT s.* FROM lr_s0 s
    WHERE s.hp > 0 AND NOT EXISTS (SELECT 1 FROM lr_death d WHERE d.game_id = s.game_id AND d.pid = s.pid AND s.sec > d.dsec AND s.sec <= d.esec)
),
-- ecx, ecy: where the enemies in reach stand (their mean position).
lr_p AS MATERIALIZED (
    SELECT game_id, pid, sec, coalesce(sum(er), 0) AS en_r, coalesce(sum(en), 0) AS en12, coalesce(sum(an), 0) AS al12,
        sqrt(min(CASE WHEN enemy THEN d2 END)) AS en_d, avg(CASE WHEN er THEN bx END) AS ecx, avg(CASE WHEN er THEN by_ END) AS ecy
    FROM (
        SELECT a.game_id, a.pid, a.sec, b.x AS bx, b.y AS by_, b.team <> a.team AS enemy,
            (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) AS d2,
            b.team <> a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= (b.ar + 600) * (b.ar + 600) AS er,
            b.team <> a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= 1200 * 1200 AS en,
            b.team = a.team AND (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) <= 1200 * 1200 AS an
        FROM lr_s a LEFT JOIN lr_s b ON b.game_id = a.game_id AND b.sec = a.sec AND b.pid <> a.pid
    )
    GROUP BY game_id, pid, sec
),
-- Tower positions (team, x, y): dynamic.js TOWERS, kept equal by a test (as fragment core_death's `tw`).
lr_tw (team, x, y) AS (VALUES
    (2, -3952, -6112), (2, -4640, -4144), (2, -6592, -3408), (2, -360, -6256), (2, 4860, -6379), (2, -3190, -2926),
    (2, -6501, -872), (2, -6336, 1856), (2, -5712, -4864), (2, -5392, -5192), (2, -1544, -1408),
    (3, 4944, 4776), (3, -128, 6016), (3, -5275, 6036), (3, 2496, 2112), (3, 524, 652), (3, 6400, 384), (3, 6336, 3032),
    (3, 3552, 5776), (3, 4272, 3759), (3, 5280, 4432), (3, 6269, -2240)),
lr_f AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.team, a.pos, a.side, a.sec, a.x, a.y, a.hp, a.hit, a.mode, a.lvl, a.ld, a.fnt2,
        p.en_r, p.en12, p.al12, coalesce(p.en_d, 99999) AS en_d, p.ecx, p.ecy,
        (SELECT min((t.x - a.x) * (t.x - a.x) + (t.y - a.y) * (t.y - a.y)) FROM lr_tw t WHERE t.team = a.team) AS own_tw2,
        (SELECT min((t.x - a.x) * (t.x - a.x) + (t.y - a.y) * (t.y - a.y)) FROM lr_tw t WHERE t.team <> a.team) AS en_tw2
    FROM lr_s a JOIN lr_p p ON p.game_id = a.game_id AND p.pid = a.pid AND p.sec = a.sec
),
lr_d1s AS (
    SELECT f.*, lag(f.sec) OVER (PARTITION BY f.game_id, f.pid ORDER BY f.sec) AS prev FROM lr_f f
    WHERE f.en_r >= 2 AND f.en_r > f.al12 + 1 AND (f.hit > 0 OR f.hp <= 50)
),
lr_d1 AS (
    SELECT o.game_id, o.pid, o.team, o.pos, o.side, o.sec AS t, o.hp, o.en_r AS en, o.al12 AS al, o.mode, a.sec AS a_sec,
        a.en_r >= 2 AND a.en_r > a.al12 + 1 AS holds,
        sqrt((a.x - o.ecx) * (a.x - o.ecx) + (a.y - o.ecy) * (a.y - o.ecy)) - sqrt((o.x - o.ecx) * (o.x - o.ecx) + (o.y - o.ecy) * (o.y - o.ecy)) >= 300
            OR a.own_tw2 <= 800 * 800 OR a.fnt2 <= 1500 * 1500 AS went,
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
-- ln2: the squared distance to our own lane's front in a tail second (NULL elsewhere, or with no ev=front line).
lr_r3 AS (
    SELECT r.*, CASE WHEN r.sec > coalesce(r.last_thr, -1) AND r.hp >= 50 THEN (
        SELECT CASE WHEN r.pos = 2 THEN (f.midx - r.x) * (f.midx - r.x) + (f.midy - r.y) * (f.midy - r.y)
                    WHEN (r.team = 2) = (r.pos IN (1, 5)) THEN (f.botx - r.x) * (f.botx - r.x) + (f.boty - r.y) * (f.boty - r.y)
                    ELSE (f.topx - r.x) * (f.topx - r.x) + (f.topy - r.y) * (f.topy - r.y) END
        FROM ev_front f WHERE f.game_id = r.game_id AND f.team = r.team AND f.t <= r.sec + 0.5 ORDER BY f.t DESC LIMIT 1) END AS ln2
    FROM lr_r2 r
),
lr_d3e AS (
    SELECT game_id, pid, team, pos, side, ep, min(sec) AS t, max(sec) - min(sec) + 1 AS span, max(hp0) AS hp,
        max(tw0) <= 750 * 750 AS start_tower, sum(en_tw2 <= 750 * 750) AS tower_s,
        sum(sec > coalesce(last_thr, -1) AND hp >= 50 AND (ln2 IS NULL OR ln2 < fnt2)) AS tail_s, max(fnt2 <= 1500 * 1500) AS fountain
    FROM lr_r3 GROUP BY game_id, pid, ep
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
    SELECT q.*, lag(q.apart) OVER w AS prev_apart, lag(q.sec) OVER w AS prev_sec,
        max(CASE WHEN q.tog THEN q.sec END) OVER (w ROWS UNBOUNDED PRECEDING) AS last_tog
    FROM lr_ps q WINDOW w AS (PARTITION BY q.game_id, q.sup ORDER BY q.sec)
),
lr_dep AS (
    SELECT d.*, row_number() OVER (PARTITION BY d.game_id, d.sup, d.last_tog ORDER BY d.sec) AS nth
    FROM lr_pw d WHERE d.apart AND d.prev_sec = d.sec - 1 AND NOT d.prev_apart AND d.last_tog >= d.sec - 15
),
lr_d7 AS (
    SELECT d.game_id, d.sup AS pid, d.team, d.spos AS pos, d.side, d.sec AS t, d.smode AS mode, d.chp AS hp, d.cen AS en,
        EXISTS (SELECT 1 FROM lr_ps n WHERE n.game_id = d.game_id AND n.sup = d.sup AND n.sec >= d.last_tog AND n.sec <= d.sec AND n.need) AS needed
    FROM lr_dep d WHERE d.nth = 1
),
lr_tf AS (
    SELECT f.*, lag(f.ld) OVER w AS pld, lag(f.sec) OVER w AS psec FROM lr_f f WINDOW w AS (PARTITION BY f.game_id, f.pid ORDER BY f.sec)
),
lr_t0 AS (
    SELECT f.*, CASE WHEN lag(f.sec) OVER w IS NULL OR f.sec - lag(f.sec) OVER w > 3 THEN 1 ELSE 0 END AS nw
    FROM lr_tf f WHERE f.ld > 1200 AND f.fnt2 > 2500 * 2500 AND f.sec >= 30
    WINDOW w AS (PARTITION BY f.game_id, f.pid ORDER BY f.sec)
),
lr_t1 AS (SELECT r.*, sum(r.nw) OVER (PARTITION BY r.game_id, r.pid ORDER BY r.sec) AS ep FROM lr_t0 r),
lr_d9e AS (
    SELECT game_id, pid, team, pos, side, ep, min(sec) AS t, max(sec) AS t1, max(sec) - min(sec) + 1 AS secs,
        sum(en_r >= 2 AND al12 = 0) AS exposed, max(CASE WHEN en_r >= 2 AND al12 = 0 THEN en_r END) AS en, min(hp) AS hp,
        (SELECT coalesce(r.mode, '') || ' ' || coalesce(r.pld <= 1200 AND r.sec - r.psec <= 3, 0) FROM lr_t1 r
            WHERE r.game_id = x.game_id AND r.pid = x.pid AND r.ep = x.ep ORDER BY r.sec LIMIT 1) AS start
    FROM lr_t1 x GROUP BY game_id, pid, ep
),
lr_d9 AS (
    SELECT e.*, substr(e.start, 1, instr(e.start, ' ') - 1) AS mode,
        EXISTS (SELECT 1 FROM lr_death d WHERE d.game_id = e.game_id AND d.pid = e.pid AND d.dsec >= e.t AND d.dsec <= e.t1 + 2) AS died
    FROM lr_d9e e
    WHERE e.t <= coalesce(:until, 720) AND e.secs >= 3 AND e.start NOT LIKE 'retreat %' AND e.start LIKE '% 1'
),
lr_d24o AS MATERIALIZED (
    SELECT o.game_id, o.pid, o.team, o.pos, o.side, o.sec AS t, o.x, o.y, o.hp, o.en_r AS en, o.al12 AS al, o.mode,
        (SELECT f.seq FROM ev_front f WHERE f.game_id = o.game_id AND f.team = o.team AND f.t <= o.sec + 0.5 ORDER BY f.t DESC LIMIT 1) AS fseq
    FROM lr_f o
    WHERE o.mode = 'retreat'
        AND NOT EXISTS (SELECT 1 FROM lr_f z WHERE z.game_id = o.game_id AND z.pid = o.pid AND z.sec >= o.sec - 3 AND z.sec < o.sec AND z.mode = 'retreat')
        AND o.sec >= 90 AND o.sec <= coalesce(:until, 720) AND o.en_r >= 1 AND o.en_r <= o.al12 + 1 AND o.hp >= 50
        AND o.en_tw2 > 750 * 750 AND o.fnt2 > 1500 * 1500
),
lr_d24 AS (
    SELECT o.*,
        (SELECT count(*) FROM lr_s b WHERE b.game_id = o.game_id AND b.sec = o.t AND b.team <> o.team
            AND (b.x - o.x) * (b.x - o.x) + (b.y - o.y) * (b.y - o.y) <= (b.ar + 600) * (b.ar + 600)
            AND NOT EXISTS (SELECT 1 FROM ev_front f WHERE f.seq = o.fseq AND f.game_id = o.game_id AND (
                (b.x - f.topx) * (b.x - f.topx) + (b.y - f.topy) * (b.y - f.topy) <= 500 * 500
                OR (b.x - f.midx) * (b.x - f.midx) + (b.y - f.midy) * (b.y - f.midy) <= 500 * 500
                OR (b.x - f.botx) * (b.x - f.botx) + (b.y - f.boty) * (b.y - f.boty) <= 500 * 500))
        ) AS free_n
    FROM lr_d24o o
),
lr_hn AS MATERIALIZED (
    SELECT DISTINCT b.game_id, b.team, 'npc_dota_hero_' || b.hero AS unit FROM ev_bot b JOIN gm ON gm.game_id = b.game_id
    WHERE b.team IS NOT NULL AND b.hero IS NOT NULL
),
lr_hb0 AS MATERIALIZED (
    SELECT o.game_id, o.pid, o.team, o.pos, o.side, o.sec AS t, o.x, o.y, o.hp, o.en_r AS en, o.al12 AS al, o.mode,
        (SELECT f.seq FROM ev_front f WHERE f.game_id = o.game_id AND f.team = o.team AND f.t <= o.sec + 0.5 ORDER BY f.t DESC LIMIT 1) AS fseq
    FROM lr_f o
    WHERE o.hit > 0 AND o.mode IS NOT 'retreat' AND o.hp >= 50 AND o.en_r >= 1 AND o.en_r <= o.al12 + 1
        AND o.en_tw2 > 750 * 750 AND o.sec >= 90 AND o.sec <= coalesce(:until, 720)
),
lr_hb1 AS (
    SELECT o.*, lag(o.t) OVER (PARTITION BY o.game_id, o.pid ORDER BY o.t) AS prev
    FROM lr_hb0 o
    WHERE EXISTS (SELECT 1 FROM lr_s b JOIN ev_front f ON f.seq = o.fseq AND f.game_id = o.game_id
        WHERE b.game_id = o.game_id AND b.sec = o.t AND b.team <> o.team
            AND (b.x - o.x) * (b.x - o.x) + (b.y - o.y) * (b.y - o.y) <= (b.ar + 600) * (b.ar + 600)
            AND ((b.x - f.topx) * (b.x - f.topx) + (b.y - f.topy) * (b.y - f.topy) <= 500 * 500
                OR (b.x - f.midx) * (b.x - f.midx) + (b.y - f.midy) * (b.y - f.midy) <= 500 * 500
                OR (b.x - f.botx) * (b.x - f.botx) + (b.y - f.boty) * (b.y - f.boty) <= 500 * 500))
),
lr_hb AS (
    SELECT o.*,
        EXISTS (SELECT 1 FROM lr_s a JOIN lr_hn n ON n.game_id = a.game_id AND n.team <> o.team AND n.unit = a.tgt
            WHERE a.game_id = o.game_id AND a.pid = o.pid AND a.sec >= o.t AND a.sec <= o.t + 3) AS hb,
        EXISTS (SELECT 1 FROM lr_s a WHERE a.game_id = o.game_id AND a.pid = o.pid AND a.sec > o.t AND a.sec <= o.t + 3 AND a.mode = 'retreat') AS went,
        (SELECT min(d.dsec) FROM lr_death d WHERE d.game_id = o.game_id AND d.pid = o.pid AND d.dsec >= o.t AND d.dsec <= o.t + 5) AS died
    FROM lr_hb1 o
    WHERE o.prev IS NULL OR o.t - o.prev > 5
),
lr_case AS (
    SELECT 'D1' AS rule, game_id, pid, team, pos, side, t,
        died IS NOT NULL OR (a_sec IS NOT NULL AND NOT coalesce(went, 0) AND holds) AS viol,
        CASE WHEN died IS NOT NULL THEN 'died' WHEN a_sec IS NULL THEN 'unseen' WHEN went THEN 'left' WHEN holds THEN 'stayed' ELSE 'ended' END AS cause,
        hp, en, al, NULL AS secs, mode
    FROM lr_d1
    UNION ALL
    SELECT 'D2', game_id, pid, team, pos, side, t, 1, side || '_retreat', hp, 0, NULL, secs, mode FROM lr_d2v
    UNION ALL
    SELECT 'D3', game_id, pid, team, pos, side, t, why IS NOT NULL, coalesce(why, 'ok'), hp, NULL, NULL, span, 'retreat' FROM lr_d3
    UNION ALL
    SELECT 'D7', game_id, pid, team, pos, side, t, needed AND mode IS NOT 'retreat',
        CASE WHEN mode = 'retreat' THEN 'self' WHEN needed THEN 'needed' ELSE 'free' END, hp, en, NULL, NULL, mode FROM lr_d7
    UNION ALL
    SELECT 'D9', game_id, pid, team, pos, side, t, exposed > 0, CASE WHEN exposed = 0 THEN 'safe' WHEN died THEN 'died' ELSE 'exposed' END,
        hp, en, 0, secs, mode
    FROM lr_d9
    UNION ALL
    SELECT 'D24', game_id, pid, team, pos, side, t, free_n = 0, CASE WHEN free_n > 0 THEN 'free_hit' ELSE side || '_retreat' END,
        hp, en, al, NULL, mode
    FROM lr_d24
    UNION ALL
    SELECT 'D24h', game_id, pid, team, pos, side, t, NOT hb,
        CASE WHEN hb THEN 'hit_back' WHEN went THEN 'left' WHEN died IS NOT NULL THEN 'died' ELSE 'none' END, hp, en, al, NULL, mode
    FROM lr_hb
),
