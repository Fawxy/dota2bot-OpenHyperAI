-- Drills (bot humaniser/drill.ts; master docs/proposals/2026-11-08-drills.md): one row per rep and cast hero, in drill games
-- whose file matches :like (and drill :name when given). A rep runs from its `ev=drill ph=rep` start to the next rep's start
-- (the last ends at the hero's last snapshot; a rep cut to under 5 s by the game's end is dropped). Per rep: input (on, or off for a control rep), the cast hero's last hits,
-- denies and deaths gained, HP-% lost (the sum of drops between 1 s snapshots, so a heal does not hide a hit), and the
-- forced context's own result lines inside the rep: `results` (ev=stack lines for drill `stack`) and `ok` (those with
-- res=stacked). A context with no join here reads its own lines over the rep window (`start`, `stop`).
-- A rig's rep (an entry with `rig`, slice drill-rig) is kept only when its cast reached ready (`ev=drill ph=ready ok=1`): its
-- row carries the rep kind `var` and `released` (the ready second, from which the graded part runs); `ready_n` of `ready_m`
-- counts the game's ready lines for that cast (the rig's acceptance). Reps of drills without ready lines are all kept.
-- ensure: ev_drill(ph, name, pid, team, pos, role, rep, input, start, forces, var, ok, fail)
-- ensure: ev_stack(pid, min, res, why)
WITH
gm AS MATERIALIZED (
    SELECT DISTINCT d.game_id FROM ev_drill d JOIN games g ON g.game_id = d.game_id
    WHERE d.ph = 'rep' AND g.file LIKE coalesce(:like, '%') AND (:name IS NULL OR d.name = :name)
),
cast AS MATERIALIZED (
    SELECT r.game_id, r.pid, r.team, r.pos, r.name FROM ev_drill r JOIN gm USING (game_id)
    WHERE r.ph = 'role' AND r.role = 'cast'
    GROUP BY r.game_id, r.pid
),
reps AS MATERIALIZED (
    SELECT d.game_id, d.name, d.team, d.rep, d.input, d.start, d.forces,
        lead(d.start) OVER (PARTITION BY d.game_id, d.team ORDER BY d.rep) AS next
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'rep'
),
sn AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t, s.hp, s.lh, s.dn, s.deaths,
        lag(s.hp) OVER (PARTITION BY s.game_id, s.pid ORDER BY s.t) AS php
    FROM ev_snap s JOIN cast c ON c.game_id = s.game_id AND c.pid = s.pid
),
rd AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.rep, max(d.ok) AS ok, min(d.t) AS released, max(d.var) AS var
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'ready' GROUP BY d.game_id, d.pid, d.rep
),
rn AS MATERIALIZED (
    SELECT game_id, pid, sum(ok = 1) AS ready_n, count(*) AS ready_m FROM rd GROUP BY game_id, pid
),
rc0 AS (
    SELECT r.*, c.pid, c.pos, coalesce(r.next, (SELECT max(t) FROM sn WHERE sn.game_id = r.game_id AND sn.pid = c.pid)) AS stop
    FROM reps r JOIN cast c ON c.game_id = r.game_id AND c.team = r.team
),
-- A rig rep is graded from its release: the forced setup (the attack that brings the cast's HP down) is not counted.
rc AS (
    SELECT rc0.*, coalesce((SELECT rd.released FROM rd WHERE rd.game_id = rc0.game_id AND rd.pid = rc0.pid AND rd.rep = rc0.rep AND rd.ok = 1), rc0.start) AS g0
    FROM rc0
)
SELECT rc.game_id, g.file, rc.name, rc.team, rc.pid, rc.pos, rc.rep, rc.input, rc.start, rc.stop, rc.forces,
    rd.var, CASE WHEN rd.ok = 1 THEN rd.released END AS released, rn.ready_n, rn.ready_m,
    (SELECT max(lh) - min(lh) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.g0 AND sn.t <= rc.stop) AS lh,
    (SELECT max(dn) - min(dn) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.g0 AND sn.t <= rc.stop) AS dn,
    (SELECT max(deaths) - min(deaths) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.g0 AND sn.t <= rc.stop) AS deaths,
    (SELECT coalesce(sum(CASE WHEN php > hp THEN php - hp ELSE 0 END), 0) FROM sn
        WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t > rc.g0 AND sn.t <= rc.stop) AS hp_lost,
    CASE WHEN rc.forces = 'stack' THEN (SELECT count(*) FROM ev_stack s WHERE s.game_id = rc.game_id AND s.pid = rc.pid
        AND s.t >= rc.g0 AND s.t < rc.stop) END AS results,
    CASE WHEN rc.forces = 'stack' THEN (SELECT count(*) FROM ev_stack s WHERE s.game_id = rc.game_id AND s.pid = rc.pid
        AND s.t >= rc.g0 AND s.t < rc.stop AND s.res = 'stacked') END AS ok
FROM rc JOIN games g ON g.game_id = rc.game_id
LEFT JOIN rd ON rd.game_id = rc.game_id AND rd.pid = rc.pid AND rd.rep = rc.rep
LEFT JOIN rn ON rn.game_id = rc.game_id AND rn.pid = rc.pid
WHERE rc.stop >= rc.start + 5
    -- A rig game (its cast logged ready lines) keeps only the reps that reached ready.
    AND (rn.ready_m IS NULL OR rd.ok = 1)
ORDER BY rc.game_id, rc.team, rc.pid, rc.rep;
