-- WO-025 telemetry gate inputs for one game (replaces the gate half of lasthit_cause.js; the thresholds stay in lasthit_cause.js).
-- Params: file (absolute log path, as in games.file), game (default 1), until (s, default 600). One row:
--   deaths, revives (before `until`): G2 is revives / deaths
--   telemetry_errors (any time): G3, ev=lua_error whose `where` starts with Telemetry
--   deny_r, deny_d: deaths of the Radiant / Dire creeps credited as `deny`; dn_r, dn_d: the deny counters of the opposing team's
--     heroes at `until` (G4 per team: deny_r / dn_d, deny_d / dn_r)
--   own, on_it, neg_a: G5, own = a core's own last hits with a distance logged, on_it = of those, on the creep it was attacking
--     (a target held, or a swing begun 0-2 s before); neg_a = core attack ages below 0 (bad clock or handle)
--   deaths_r, deaths_d: G6, creep deaths per team
-- Constants: the G5 attack age (<= 2 s) is here only; the other thresholds are in lasthit_cause.js `GATE`.
-- The deny and revive shares are divided in lasthit_cause.js.
-- ensure: ev_creep_death(team, by, p1d, p1t, p1a, p2d, p2t, p2a, p3d, p3t, p3a)
-- ensure: ev_creep_revive(team)
-- ensure: ev_lua_error(where)
-- ensure: ev_snap(pid, x, dn)
-- ensure: ev_bot(pid, team, pos)
WITH gm AS (SELECT game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
deaths AS (
    SELECT team, "by" AS killer, p1d, p1t, p1a, p2d, p2t, p2a, p3d, p3t, p3a
    FROM ev_creep_death
    WHERE game_id = (SELECT game_id FROM gm) AND t < coalesce(:until, 600)
),
cores AS (
    SELECT l.team, l.pos, l.pid FROM lineup l
    WHERE l.game_id = (SELECT game_id FROM gm) AND l.pos BETWEEN 1 AND 3
      AND EXISTS (SELECT 1 FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL)
),
bt AS (
    SELECT r.pid, r.team FROM (
        SELECT pid, team, row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn
        FROM ev_bot WHERE game_id = (SELECT game_id FROM gm) AND team IS NOT NULL
    ) r WHERE r.rn = 1 AND EXISTS (SELECT 1 FROM ev_snap s WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = r.pid AND s.x IS NOT NULL)
),
dn AS (
    SELECT bt.team, coalesce((SELECT s.dn FROM ev_snap s
        WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = bt.pid AND s.x IS NOT NULL AND s.dn IS NOT NULL AND s.t <= coalesce(:until, 600)
        ORDER BY s.t DESC, s.seq DESC LIMIT 1), 0) AS dn
    FROM bt
),
own AS (
    SELECT d.*, c.pos,
        CASE c.pos WHEN 1 THEN d.p1d WHEN 2 THEN d.p2d ELSE d.p3d END AS pd,
        CASE c.pos WHEN 1 THEN d.p1t WHEN 2 THEN d.p2t ELSE d.p3t END AS pt,
        CASE c.pos WHEN 1 THEN d.p1a WHEN 2 THEN d.p2a ELSE d.p3a END AS pa
    FROM deaths d JOIN cores c ON CAST(d.killer AS TEXT) = CAST(c.pid AS TEXT) AND d.team = c.team
)
SELECT (SELECT file FROM games WHERE game_id = (SELECT game_id FROM gm)) AS file, coalesce(:game, 1) AS game,
    (SELECT count(*) FROM deaths) AS deaths,
    (SELECT count(*) FROM ev_creep_revive WHERE game_id = (SELECT game_id FROM gm) AND t < coalesce(:until, 600)) AS revives,
    (SELECT count(*) FROM ev_lua_error WHERE game_id = (SELECT game_id FROM gm) AND "where" GLOB 'Telemetry*') AS telemetry_errors,
    (SELECT count(*) FROM deaths WHERE team = 2 AND killer = 'deny') AS deny_r,
    (SELECT count(*) FROM deaths WHERE team = 3 AND killer = 'deny') AS deny_d,
    (SELECT coalesce(sum(dn), 0) FROM dn WHERE team = 2) AS dn_r,
    (SELECT coalesce(sum(dn), 0) FROM dn WHERE team = 3) AS dn_d,
    (SELECT count(*) FROM own WHERE pd IS NOT NULL) AS own,
    (SELECT count(*) FROM own WHERE pd IS NOT NULL
        AND (pt = 1 OR (typeof(pa) IN ('integer', 'real') AND pa >= 0 AND pa <= 2))) AS on_it,
    (SELECT coalesce(sum((typeof(p1a) IN ('integer', 'real') AND p1a < 0) + (typeof(p2a) IN ('integer', 'real') AND p2a < 0)
        + (typeof(p3a) IN ('integer', 'real') AND p3a < 0)), 0) FROM deaths) AS neg_a,
    (SELECT count(*) FROM deaths WHERE team = 2) AS deaths_r,
    (SELECT count(*) FROM deaths WHERE team = 3) AS deaths_d
