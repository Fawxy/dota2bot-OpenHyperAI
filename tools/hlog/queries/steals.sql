-- Audited steals (slice 3, KR H.2; replaces dynamic.js `auditedSteals`): every lane creep that an own pos4/pos5 last-hit before `until`
-- while an own core logged on it was attacking it (p<N>t = 1) or within its attack range + 150 (p<N>d <= p<N>r + 150), one row per creep.
-- Params: file (absolute log path, as in games.file), game (default 1), until (s, default 600). Rows:
--   kind 'case': t, team, pid, pos, mode, snap_mode, swing, creep_kind, then c<N>d, c<N>r, c<N>t for the three logged cores
--     (mode = the swing-start mode `bm` when logged, else snap_mode = the killer's latest ev=snap mode at or before the whole second of t)
--   kind 'game' (one): deaths = ev=creep_death rows of the game (any time), lined = heroes with a trusted lineup position;
--     no deaths or no lined heroes means "no audit possible" (steals.js says so; zero cases would be a result)
-- Lineup is trusted per team only when its five heroes (every hero with a team and a located snap, humans too) hold positions 1-5
-- once each (a pre-Dire-fix log, or a human on the team, leaves the team without positions), as dynamic.js `lpos`; the `lineup` view is not used.
-- `+game_id` in gm: a plain column compared with a subquery value cannot use the game_id index, a unary plus on the value lets it.
-- Constants: the 150 above, from dynamic.js `C.AUDIT_BUF`; test/steals.test.js pins the boundary.
-- ensure: ev_creep_death(team, kind, by, p1d, p1r, p1t, p2d, p2r, p2t, p3d, p3r, p3t, bm, bs)
-- ensure: ev_snap(pid, x, mode)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_player(pid, team)
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
tm AS (
    SELECT pid, team FROM (
        SELECT pid, team, row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn
        FROM (SELECT seq, pid, team FROM ev_bot WHERE game_id = (SELECT game_id FROM gm)
              UNION ALL SELECT seq, pid, team FROM ev_player WHERE game_id = (SELECT game_id FROM gm))
    ) WHERE rn = 1 AND team IS NOT NULL
),
ps AS (
    SELECT pid, pos FROM (
        SELECT pid, pos, row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn
        FROM ev_bot WHERE game_id = (SELECT game_id FROM gm) AND typeof(pos) IN ('integer', 'real')
    ) WHERE rn = 1
),
sx AS (
    SELECT DISTINCT pid FROM ev_snap WHERE game_id = (SELECT game_id FROM gm) AND typeof(x) IN ('integer', 'real')
),
sb AS (
    SELECT tm.pid, tm.team, ps.pos FROM tm LEFT JOIN ps USING (pid) WHERE tm.pid IN (SELECT pid FROM sx)
),
ok AS (
    SELECT team FROM sb GROUP BY team
    HAVING count(*) = 5 AND count(pos) = 5 AND count(DISTINCT pos) = 5 AND min(pos) = 1 AND max(pos) = 5
),
lp AS (SELECT pid, team, pos FROM sb WHERE team IN (SELECT team FROM ok)),
cd AS (
    SELECT seq, t, team, kind, "by" AS killer, bm, bs, p1d, p1r, p1t, p2d, p2r, p2t, p3d, p3r, p3t
    FROM ev_creep_death WHERE game_id = (SELECT game_id FROM gm)
)
SELECT 'case' AS kind, cd.t, cd.team, lp.pid, lp.pos,
    coalesce(cd.bm, (SELECT s.mode FROM ev_snap s
        WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = lp.pid AND typeof(s.x) IN ('integer', 'real') AND s.t <= cast(cd.t AS INTEGER)
        ORDER BY s.t DESC, s.seq DESC LIMIT 1)) AS mode,
    (SELECT s.mode FROM ev_snap s
        WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = lp.pid AND typeof(s.x) IN ('integer', 'real') AND s.t <= cast(cd.t AS INTEGER)
        ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS snap_mode,
    cd.bs AS swing, cd.kind AS creep_kind,
    cd.p1d AS c1d, cd.p1r AS c1r, cd.p1t AS c1t, cd.p2d AS c2d, cd.p2r AS c2r, cd.p2t AS c2t, cd.p3d AS c3d, cd.p3r AS c3r, cd.p3t AS c3t,
    NULL AS deaths, NULL AS lined
FROM cd JOIN lp ON CAST(cd.killer AS TEXT) = CAST(lp.pid AS TEXT) AND lp.pos >= 4
WHERE cd.t < coalesce(:until, 600)
  AND (cd.p1t = 1 OR cd.p1d <= cd.p1r + 150 OR cd.p2t = 1 OR cd.p2d <= cd.p2r + 150 OR cd.p3t = 1 OR cd.p3d <= cd.p3r + 150)
UNION ALL
SELECT 'game', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    (SELECT count(*) FROM cd), (SELECT count(*) FROM lp)
ORDER BY 1, 2
