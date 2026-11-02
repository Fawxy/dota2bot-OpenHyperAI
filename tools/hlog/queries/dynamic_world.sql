-- World-event metrics of one game (dynamic.js part C, docs/team/slices/retire-dynamic-c.md; definitions from slice 23), as rows
-- dynamicMetrics' `worldMetrics` reads; roles stay in JS, so the role-dependent keys (mid rune shares, first sentry per support)
-- come as per-hero rows and JS applies the roles. Counts only: JS divides, so shares are the same floats as before.
-- Params: file (absolute log path, as in games.file), game (default 1). Rows by `kind`:
--   'game' (one)  world = 1 when the game logged any ev=rune_pickup, ward_place, building_fall or tp (older builds did not: JS
--                 reads undefined for every event metric then, except wisdom); t1 = the first tier-1 tower fall; rosh = the first
--                 Roshan kill (ev=roshan_kill, one kill per distinct `at`, timed by log t: the time base of `at` is unverified);
--                 rosh_open = kills with 240 s left before `end`, rosh_ok = those followed within 240 s by a building fall of the
--                 team that did not pick up the aegis (the first ev=aegis in log order within 30 s of the kill names the killers;
--                 with none, any fall counts) (`C.ROSH_FOLLOW`, `C.AEGIS_AFTER`)
--   'team' (2 and 3)  sentry90 = 1 when the team placed a sentry by 1:30 (`C.SENTRY_BY`); smokes = ev=smoke_use from the horn, one
--                 smoke within 3 s of its group's first joining it (`C.SMOKE_MERGE`); tpj = ev=tp in [10:00, 30:00) that moved over
--                 1000 units (`C.TP_MOVED`) and landed within 1200 of an alive ally at the second before, of or after it
--                 (`C.TP_JOIN_R`); bursts = 3+ deaths of the other team no more than 15 s apart (hero_death; `C.FIGHT_GAP`,
--                 `C.FIGHT_MIN_DEATHS`) whose last death has 120 s left before `end`, cashed = those followed within 120 s by a
--                 fall of a building not the team's own (`C.CASH_IN`); fills = the team's Shrine of Wisdom fills (7:00, then
--                 every 7:00, to `end` - 15 s), taken = fills some hero takes: alive within 300 of the shrine for 3 seconds in a
--                 row, the run starting by fill + 15 s (a snapshot proxy; `C.WISDOM_*`, shrine spots from states/rotate.ts)
--   'rune'        per team, picker pid and rune kind (power, water): n pickups
--   'sentry'      per pid: t of its first ev=ward_place sentry in log order
-- ensure: ev_rune_pickup(pid, team, kind)
-- ensure: ev_ward_place(pid, team, kind)
-- ensure: ev_smoke_use(team)
-- ensure: ev_tp(pid, team, x, y, dist)
-- ensure: ev_building_fall(team, kind, tier)
-- ensure: ev_roshan_kill(at)
-- ensure: ev_aegis(team)
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
-- include: hero_death
tms(team) AS (VALUES (2), (3)),
fall AS MATERIALIZED (SELECT t, team, kind, tier FROM ev_building_fall WHERE game_id = (SELECT game_id FROM gm)),
sm AS (
    SELECT team, t, row_number() OVER (PARTITION BY team ORDER BY t, seq) AS rn
    FROM ev_smoke_use WHERE game_id = (SELECT game_id FROM gm) AND t >= 0
),
smg(team, rn, first, n) AS (
    SELECT team, rn, t, 1 FROM sm WHERE rn = 1
    UNION ALL
    SELECT s.team, s.rn, CASE WHEN s.t - g.first > 3 THEN s.t ELSE g.first END, g.n + (s.t - g.first > 3)
    FROM smg g JOIN sm s ON s.team IS g.team AND s.rn = g.rn + 1
),
tpj AS (
    SELECT e.team, count(*) AS n FROM ev_tp e
    WHERE e.game_id = (SELECT game_id FROM gm) AND e.t >= 600 AND e.t < 1800 AND NOT coalesce(e.dist <= 1000, 0)
      AND EXISTS (SELECT 1 FROM hs_sec o
                  WHERE o.team = e.team AND o.pid IS NOT e.pid AND o.alive IS NOT 0
                    AND o.s BETWEEN CAST(floor(e.t) AS INTEGER) - 1 AND CAST(floor(e.t) AS INTEGER) + 1
                    AND sqrt((o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y)) <= 1200)
    GROUP BY e.team
),
dd AS (SELECT k.team AS tm, d.t, d.n, row_number() OVER (PARTITION BY k.team ORDER BY d.t) AS rn FROM death d JOIN tms k ON d.team IS NOT k.team),
drun AS (
    SELECT tm, t, n, sum(brk) OVER (PARTITION BY tm ORDER BY rn ROWS UNBOUNDED PRECEDING) AS id
    FROM (SELECT tm, t, n, rn, CASE WHEN t - lag(t) OVER (PARTITION BY tm ORDER BY rn) <= 15 THEN 0 ELSE 1 END AS brk FROM dd)
),
burst AS (
    SELECT tm AS team, b FROM (SELECT tm, max(t) AS b FROM drun GROUP BY tm, id HAVING sum(n) >= 3)
    WHERE b + 120 <= (SELECT e FROM hs_end)
),
fill(f) AS (
    SELECT 420 WHERE 435 <= (SELECT e FROM hs_end)
    UNION ALL
    SELECT f + 420 FROM fill WHERE f + 435 <= (SELECT e FROM hs_end)
),
shr(team, sx, sy) AS (VALUES (2, -7948, 768), (3, 8029, -1126)),
near AS MATERIALIZED (
    SELECT k.team, h.pid, h.s FROM hs_sec h JOIN shr k
    WHERE h.alive IS NOT 0 AND sqrt((h.x - k.sx) * (h.x - k.sx) + (h.y - k.sy) * (h.y - k.sy)) <= 300
),
wis AS (
    SELECT k.team, count(*) AS fills,
        sum(EXISTS (SELECT 1 FROM near a JOIN near b ON b.team = a.team AND b.pid = a.pid AND b.s = a.s + 1
                    JOIN near c ON c.team = a.team AND c.pid = a.pid AND c.s = a.s + 2
                    WHERE a.team = k.team AND a.s BETWEEN f.f AND f.f + 15)) AS taken
    FROM shr k CROSS JOIN fill f GROUP BY k.team
),
rosh AS (SELECT "at", min(t) AS t FROM ev_roshan_kill WHERE game_id = (SELECT game_id FROM gm) GROUP BY "at"),
ropen AS (
    SELECT r.t, EXISTS (SELECT 1 FROM ev_aegis a WHERE a.game_id = (SELECT game_id FROM gm) AND a.t >= r.t AND a.t <= r.t + 30) AS aeg,
        (SELECT a.team FROM ev_aegis a WHERE a.game_id = (SELECT game_id FROM gm) AND a.t >= r.t AND a.t <= r.t + 30
         ORDER BY a.seq LIMIT 1) AS ateam
    FROM rosh r WHERE r.t + 240 <= (SELECT e FROM hs_end)
)
SELECT 'game' AS kind, NULL AS team, NULL AS pid, NULL AS rune, NULL AS n, NULL AS t,
    (EXISTS (SELECT 1 FROM ev_rune_pickup WHERE game_id = (SELECT game_id FROM gm))
     OR EXISTS (SELECT 1 FROM ev_ward_place WHERE game_id = (SELECT game_id FROM gm))
     OR EXISTS (SELECT 1 FROM fall)
     OR EXISTS (SELECT 1 FROM ev_tp WHERE game_id = (SELECT game_id FROM gm))) AS world,
    (SELECT min(t) FROM fall WHERE kind = 'tower' AND tier = 1) AS t1,
    (SELECT min(t) FROM rosh) AS rosh,
    (SELECT count(*) FROM ropen) AS rosh_open,
    (SELECT count(*) FROM ropen r WHERE EXISTS (SELECT 1 FROM fall f WHERE f.t > r.t AND f.t <= r.t + 240
                                              AND (NOT r.aeg OR f.team IS NOT r.ateam))) AS rosh_ok,
    NULL AS sentry90, NULL AS smokes, NULL AS tpj, NULL AS bursts, NULL AS cashed, NULL AS fills, NULL AS taken
UNION ALL
SELECT 'team', k.team, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    EXISTS (SELECT 1 FROM ev_ward_place w WHERE w.game_id = (SELECT game_id FROM gm) AND w.kind = 'sentry' AND w.team = k.team AND w.t <= 90),
    coalesce((SELECT max(n) FROM smg g WHERE g.team = k.team), 0),
    coalesce((SELECT n FROM tpj j WHERE j.team = k.team), 0),
    (SELECT count(*) FROM burst b WHERE b.team = k.team),
    (SELECT count(*) FROM burst b WHERE b.team = k.team
       AND EXISTS (SELECT 1 FROM fall f WHERE f.team IS NOT k.team AND f.t > b.b AND f.t <= b.b + 120)),
    coalesce((SELECT fills FROM wis w WHERE w.team = k.team), 0),
    coalesce((SELECT taken FROM wis w WHERE w.team = k.team), 0)
FROM tms k
UNION ALL
SELECT 'rune', team, pid, kind, count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM ev_rune_pickup WHERE game_id = (SELECT game_id FROM gm) AND kind IN ('power', 'water') GROUP BY team, pid, kind
UNION ALL
SELECT 'sentry', NULL, pid, NULL, NULL, t, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT pid, t, row_number() OVER (PARTITION BY pid ORDER BY seq) AS rn
      FROM ev_ward_place WHERE game_id = (SELECT game_id FROM gm) AND kind = 'sentry' AND pid IS NOT NULL)
WHERE rn = 1
