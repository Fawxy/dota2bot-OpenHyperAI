-- Idle-in-range lane-creep deaths with what the laning body was doing (slice 5 missed-bar attribution, ER-008; D11's view):
-- one row per enemy lane creep that died before `until` within a core's attack range + 300 (as @lasthit_cores'
-- idle_in_range) while the core (lineup position 1-3) was not attacking it and did not get it. `mode` is the core's OHA mode
-- at the last ev=snap at or before the death; `lf` the laning body's lane_pick Describe string from the last snap within
-- 1.5 s before it (NULL when the build logs no lf). Read `lf`: `sc` well above the scan period means the body was inside one
-- lastHit/deny verb (`ph` lasthit/deny) or OHA's mode was not laning.
-- `held`: our laning body had an attempt on this creep that it lost before swinging (an ev=lh lasthit that failed
-- `taken_by_other` or `denied` with a `why=`, started by the death, ended from 0.05 s before it to 2.5 s after, its creep
-- within 80 of the death point; each attempt goes to its nearest such death). `wait`: in range, the swing held for its
-- moment (K1); `range`: still walking in; `stall`: reported over 0.5 s after the creep died, so the verb was not stepped;
-- `other`: any other `why`. Only `wait` is an attempt OHA's laning would show in the creep facts (it attacks a creep in range
-- at once, but walks in with a bare move), so only `wait` rows are left out, unless held=1 (intake 12/11/2026: about 4.4 a
-- game under laning in h2hskill1); `range`, `stall` and `other` stay violations with their label. OHA has no ev=lh, so its
-- `held` is NULL. Params: file (absolute log path, as in games.file), game (default 1), until (s, default 600), held (1 to
-- keep the `wait` rows, default 0).
-- ensure: ev_snap(pid, mode, lf)
-- ensure: ev_creep_death(team, "by", p1d, p1r, p1t, p1a, p2d, p2r, p2t, p2a, p3d, p3r, p3t, p3a)
-- ensure: ev_lh(pid, kind, result, reason, cx, cy, msg)
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
c AS (SELECT game_id, team, pos, pid FROM lineup WHERE game_id = (SELECT game_id FROM gm) AND pos BETWEEN 1 AND 3),
d AS (
    SELECT e.game_id, e.seq, e.t, e.x, e.y, c.team, c.pos, c.pid, e."by" AS killer,
        CASE c.pos WHEN 1 THEN e.p1d WHEN 2 THEN e.p2d ELSE e.p3d END AS pd,
        CASE c.pos WHEN 1 THEN e.p1r WHEN 2 THEN e.p2r ELSE e.p3r END AS pr,
        CASE c.pos WHEN 1 THEN e.p1t WHEN 2 THEN e.p2t ELSE e.p3t END AS pt,
        CASE c.pos WHEN 1 THEN e.p1a WHEN 2 THEN e.p2a ELSE e.p3a END AS pa
    FROM ev_creep_death e JOIN c ON c.game_id = e.game_id AND c.team = e.team
    WHERE e.t < coalesce(:until, 600)),
idle AS (
    SELECT * FROM d
    WHERE CAST(d.killer AS TEXT) <> CAST(d.pid AS TEXT) AND d.pd <= coalesce(d.pr, 150) + 300 AND coalesce(d.pt, 0) = 0
      AND d.pa IS NULL),
pair AS (
    SELECT i.seq AS dseq, l.seq AS lseq,
        CASE WHEN l.t - i.t > 0.5 THEN 'stall' WHEN l.msg LIKE '%why=wait%' THEN 'wait'
            WHEN l.msg LIKE '%why=range%' THEN 'range' ELSE 'other' END AS why,
        row_number() OVER (PARTITION BY l.seq ORDER BY (l.cx - i.x) * (l.cx - i.x) + (l.cy - i.y) * (l.cy - i.y), abs(l.t - i.t)) AS rn
    FROM idle i JOIN ev_lh l ON l.game_id = i.game_id AND l.pid = i.pid AND l.t >= i.t - 0.05 AND l.t <= i.t + 2.5
    WHERE l.kind = 'lasthit' AND l.result = 'fail' AND l.reason IN ('taken_by_other', 'denied') AND l.msg LIKE '%why=%'
      AND l.cx IS NOT NULL AND (l.cx - i.x) * (l.cx - i.x) + (l.cy - i.y) * (l.cy - i.y) < 6400
      AND (l.msg NOT LIKE 'w=%' OR l.t - CAST(substr(l.msg, 3, instr(l.msg, ' ') - 3) AS REAL) <= i.t + 0.05)),
h AS (
    SELECT dseq, why, row_number() OVER (PARTITION BY dseq ORDER BY lseq) AS rn FROM pair WHERE rn = 1)
SELECT i.team, i.pos, i.pid, i.t,
    (SELECT s.mode FROM ev_snap s WHERE s.game_id = i.game_id AND s.pid = i.pid AND s.t <= i.t AND s.mode IS NOT NULL
        ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS mode,
    (SELECT s.lf FROM ev_snap s WHERE s.game_id = i.game_id AND s.pid = i.pid AND s.t <= i.t AND s.t > i.t - 1.5
        AND s.lf IS NOT NULL ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS lf,
    h.why AS held
FROM idle i LEFT JOIN h ON h.dseq = i.seq AND h.rn = 1
WHERE h.why IS NOT 'wait' OR coalesce(:held, 0) = 1
ORDER BY i.team, i.pos, i.t
