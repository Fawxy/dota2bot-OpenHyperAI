-- One row per hero of a game (dynamic.js part A, docs/team/slices/retire-dynamic-a.md): the inputs dynamicMetrics' roles,
-- lineup-position and per-hero keys read. Params: file (absolute log path, as in games.file), game (default 1).
--   lpos   pos of the hero's last ev=bot line that has one (dynamic.js checks each team is exactly 1-5)
--   lh10   last-hit counter of the last snapshot at or before 10:00 (0 if none)
--   home   modal lane over 1:00-5:00 (seconds alive; base and other ignored; a tie goes to the lane seen first)
--   idle   idle episodes from 0:00 to `end` (whole minutes of snapshots): alive, outside base, within 100 units of one spot
--          for 10 s, each counted once (`C.IDLE_R`, `C.IDLE_S`)
--   rot10  rotations before 10:00 (part B, docs/team/slices/retire-dynamic-b.md): from 1:00, a run of 10+ s alive in one lane other
--          than home; up to 8 s of 'other' (river, jungle) keep the run open uncounted, and another lane, base or death closes
--          it (`C.ROT_MIN_S`, `C.ROT_GAP`); 0 with no home
--   lane_exit  the first whole minute from 5:00, ending by `end`, in which under half of the seconds alive outside base are in the
--          home lane (NULL if none, or no home)
--   tp_joins  teleport-sized jumps from 10:00 to `end`: alive at s - 2, s - 1 and s, 2500+ units from s - 2 to s, landing
--          outside base; one jump counts once (the next can start 3 s later), and counts when an alive ally stands within
--          1200 of the landing at s (`C.TP_JUMP`, `C.TP_WINDOW`, `C.TP_JOIN_R`)
-- ensure: ev_bot(pid, team, hero, pos)
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
pts AS (SELECT 'sec' AS kind, pid AS k, s AS seq, s AS t, x, y FROM hs_sec),
-- include: lane_label
lane AS MATERIALIZED (
    SELECT h.pid, h.s, h.x, h.y, h.alive IS NOT 0 AS up, l.lane
    FROM hs_sec h JOIN lab l ON l.k = h.pid AND l.seq = h.s
),
home AS (
    SELECT pid, lane, row_number() OVER (PARTITION BY pid ORDER BY count(*) DESC, min(s)) AS rk
    FROM lane WHERE up AND s >= 60 AND s < 300 AND lane NOT IN ('base', 'other')
    GROUP BY pid, lane
),
idle(pid, s, ax, ay, st, n) AS (
    SELECT pid, -1, NULL, NULL, NULL, 0 FROM hs_bot
    UNION ALL
    SELECT i.pid, i.s + 1,
        CASE WHEN NOT coalesce(l.up AND l.lane <> 'base', 0) THEN NULL
             WHEN i.ax IS NULL OR sqrt((l.x - i.ax) * (l.x - i.ax) + (l.y - i.ay) * (l.y - i.ay)) > 100 THEN l.x ELSE i.ax END,
        CASE WHEN NOT coalesce(l.up AND l.lane <> 'base', 0) THEN NULL
             WHEN i.ax IS NULL OR sqrt((l.x - i.ax) * (l.x - i.ax) + (l.y - i.ay) * (l.y - i.ay)) > 100 THEN l.y ELSE i.ay END,
        CASE WHEN NOT coalesce(l.up AND l.lane <> 'base', 0) THEN i.st
             WHEN i.ax IS NULL OR sqrt((l.x - i.ax) * (l.x - i.ax) + (l.y - i.ay) * (l.y - i.ay)) > 100 THEN i.s + 1 ELSE i.st END,
        i.n + (coalesce(l.up AND l.lane <> 'base', 0) AND i.ax IS NOT NULL
               AND sqrt((l.x - i.ax) * (l.x - i.ax) + (l.y - i.ay) * (l.y - i.ay)) <= 100 AND i.s + 1 - i.st = 10)
    FROM idle i LEFT JOIN lane l ON l.pid = i.pid AND l.s = i.s + 1
    WHERE i.s + 1 < (SELECT e FROM hs_end)
),
hm AS (SELECT pid, lane AS home FROM home WHERE rk = 1),
rsec(t) AS (SELECT 60 UNION ALL SELECT t + 1 FROM rsec WHERE t < 600),
rl AS MATERIALIZED (
    SELECT pid, t, L, coalesce(L IN ('top', 'mid', 'bot') AND L <> home, 0) AS mv FROM (
        SELECT b.pid, c.t, hm.home, CASE WHEN c.t < 600 AND l.up THEN l.lane ELSE 'x' END AS L
        FROM hs_bot b CROSS JOIN rsec c LEFT JOIN hm ON hm.pid = b.pid LEFT JOIN lane l ON l.pid = b.pid AND l.s = c.t
    )
),
rot(pid, t, rl, rn, gap, cnt) AS (
    SELECT pid, 59, NULL, 0, 0, 0 FROM hs_bot
    UNION ALL
    SELECT r.pid, q.t,
        CASE WHEN q.mv THEN q.L WHEN r.rl IS NOT NULL AND q.L = 'other' AND r.gap + 1 <= 8 THEN r.rl END,
        CASE WHEN q.mv THEN (CASE WHEN r.rl = q.L THEN r.rn + 1 ELSE 1 END)
             WHEN r.rl IS NOT NULL AND q.L = 'other' AND r.gap + 1 <= 8 THEN r.rn ELSE 0 END,
        CASE WHEN NOT q.mv AND r.rl IS NOT NULL AND q.L = 'other' AND r.gap + 1 <= 8 THEN r.gap + 1 ELSE 0 END,
        r.cnt + CASE WHEN q.mv THEN (CASE WHEN r.rl IS NOT NULL AND r.rl <> q.L AND r.rn >= 10 THEN 1 ELSE 0 END)
                     WHEN r.rl IS NOT NULL AND q.L = 'other' AND r.gap + 1 <= 8 THEN 0
                     WHEN r.rl IS NOT NULL AND r.rn >= 10 THEN 1 ELSE 0 END
    FROM rot r JOIN rl q ON q.pid = r.pid AND q.t = r.t + 1
),
lx AS (
    SELECT l.pid, 300 + 60 * ((l.s - 300) / 60) AS m,
        sum(l.up AND l.lane <> 'base') AS seen, sum(l.up AND l.lane <> 'base' AND l.lane = hm.home) AS inl
    FROM lane l JOIN hm ON hm.pid = l.pid
    WHERE l.s >= 300 AND 300 + 60 * ((l.s - 300) / 60) + 60 <= (SELECT e FROM hs_end)
    GROUP BY l.pid, m
),
tpc AS MATERIALIZED (
    SELECT b.pid, l.s AS t,
        EXISTS (SELECT 1 FROM hs_sec o WHERE o.team = b.team AND o.pid <> b.pid AND o.s = l.s AND o.alive IS NOT 0
                AND sqrt((o.x - l.x) * (o.x - l.x) + (o.y - l.y) * (o.y - l.y)) <= 1200) AS ally
    FROM lane l JOIN hs_bot b ON b.pid = l.pid
    JOIN lane a ON a.pid = l.pid AND a.s = l.s - 2
    JOIN lane m ON m.pid = l.pid AND m.s = l.s - 1
    WHERE l.s >= 600 AND l.s < (SELECT e FROM hs_end) AND l.up AND a.up AND m.up AND l.lane <> 'base'
      AND sqrt((l.x - a.x) * (l.x - a.x) + (l.y - a.y) * (l.y - a.y)) >= 2500
),
tpk(pid, t) AS (
    SELECT pid, min(t) FROM tpc GROUP BY pid
    UNION ALL
    SELECT k.pid, (SELECT min(c.t) FROM tpc c WHERE c.pid = k.pid AND c.t > k.t + 2) FROM tpk k WHERE k.t IS NOT NULL
)
SELECT b.pid, b.team, b.hero,
    (SELECT e.pos FROM ev_bot e WHERE e.game_id = (SELECT game_id FROM gm) AND e.pid = b.pid AND typeof(e.pos) IN ('integer', 'real')
     ORDER BY e.seq DESC LIMIT 1) AS lpos,
    coalesce((SELECT s.lh FROM hs_snap s WHERE s.pid = b.pid AND s.t <= 600 AND typeof(s.lh) IN ('integer', 'real')
              ORDER BY s.t DESC, s.seq DESC LIMIT 1), 0) AS lh10,
    (SELECT h.lane FROM home h WHERE h.pid = b.pid AND h.rk = 1) AS home,
    (SELECT max(n) FROM idle i WHERE i.pid = b.pid) AS idle,
    (SELECT r.cnt FROM rot r WHERE r.pid = b.pid AND r.t = 600) AS rot10,
    (SELECT min(x.m) FROM lx x WHERE x.pid = b.pid AND x.seen > 0 AND 2 * x.inl < x.seen) AS lane_exit,
    (SELECT count(*) FROM tpk k JOIN tpc c ON c.pid = k.pid AND c.t = k.t WHERE k.pid = b.pid AND c.ally) AS tp_joins
FROM hs_bot b
ORDER BY b.pid
