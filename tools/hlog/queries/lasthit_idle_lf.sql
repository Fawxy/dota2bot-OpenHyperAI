-- Idle-in-range lane-creep deaths with what the laning body was doing (slice 5 missed-bar attribution, ER-008): one row per
-- enemy lane creep that died before `until` within a core's attack range + 300 (as @lasthit_cores' idle_in_range) while the
-- core (lineup position 1-3) was not attacking it and did not get it. `mode` is the core's OHA mode at the last ev=snap at or
-- before the death; `lf` the laning body's lane_pick Describe string from the last snap within 1.5 s before it (NULL when
-- the build logs no lf). Read `lf`: `sc` well above the scan period means the body was inside one lastHit/deny verb (`ph`
-- lasthit/deny) or OHA's mode was not laning. Params: file (absolute log path, as in games.file), game (default 1),
-- until (s, default 600).
-- ensure: ev_snap(pid, mode, lf)
-- ensure: ev_creep_death(team, "by", p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
c AS (SELECT game_id, team, pos, pid FROM lineup WHERE game_id = (SELECT game_id FROM gm) AND pos BETWEEN 1 AND 3),
d AS (
    SELECT e.game_id, e.t, c.team, c.pos, c.pid, e."by" AS killer,
        CASE c.pos WHEN 1 THEN e.p1d WHEN 2 THEN e.p2d ELSE e.p3d END AS pd,
        CASE c.pos WHEN 1 THEN e.p1r WHEN 2 THEN e.p2r ELSE e.p3r END AS pr,
        CASE c.pos WHEN 1 THEN e.p1t WHEN 2 THEN e.p2t ELSE e.p3t END AS pt,
        CASE c.pos WHEN 1 THEN e.p1a WHEN 2 THEN e.p2a ELSE e.p3a END AS pa
    FROM ev_creep_death e JOIN c ON c.game_id = e.game_id AND c.team = e.team
    WHERE e.t < coalesce(:until, 600))
SELECT d.team, d.pos, d.pid, d.t,
    (SELECT s.mode FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = d.pid AND s.t <= d.t AND s.mode IS NOT NULL
        ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS mode,
    (SELECT s.lf FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = d.pid AND s.t <= d.t AND s.t > d.t - 1.5
        AND s.lf IS NOT NULL ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS lf
FROM d
WHERE CAST(d.killer AS TEXT) <> CAST(d.pid AS TEXT) AND d.pd <= coalesce(d.pr, 150) + 300 AND coalesce(d.pt, 0) = 0
  AND d.pa IS NULL
ORDER BY d.team, d.pos, d.t
