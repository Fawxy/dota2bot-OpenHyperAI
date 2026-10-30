-- One row per hero of a game (dynamic.js part A, docs/team/slices/retire-dynamic-a.md): the inputs dynamicMetrics' roles,
-- lineup-position and per-hero keys read. Params: file (absolute log path, as in games.file), game (default 1).
--   lpos   pos of the hero's last ev=bot line that has one (dynamic.js checks each team is exactly 1-5)
--   lh10   last-hit counter of the last snapshot at or before 10:00 (0 if none)
--   home   modal lane over 1:00-5:00 (seconds alive; base and other ignored; a tie goes to the lane seen first)
--   idle   idle episodes from 0:00 to `end` (whole minutes of snapshots): alive, outside base, within 100 units of one spot
--          for 10 s, each counted once (`C.IDLE_R`, `C.IDLE_S`)
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
)
SELECT b.pid, b.team, b.hero,
    (SELECT e.pos FROM ev_bot e WHERE e.game_id = (SELECT game_id FROM gm) AND e.pid = b.pid AND typeof(e.pos) IN ('integer', 'real')
     ORDER BY e.seq DESC LIMIT 1) AS lpos,
    coalesce((SELECT s.lh FROM hs_snap s WHERE s.pid = b.pid AND s.t <= 600 AND typeof(s.lh) IN ('integer', 'real')
              ORDER BY s.t DESC, s.seq DESC LIMIT 1), 0) AS lh10,
    (SELECT h.lane FROM home h WHERE h.pid = b.pid AND h.rk = 1) AS home,
    (SELECT max(n) FROM idle i WHERE i.pid = b.pid) AS idle
FROM hs_bot b
ORDER BY b.pid
