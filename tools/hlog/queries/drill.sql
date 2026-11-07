-- Drills (bot humaniser/drill.ts; master docs/proposals/2026-11-08-drills.md): one row per rep and cast hero, in drill games
-- whose file matches :like (and drill :name when given). A rep runs from its `ev=drill ph=rep` start to the next rep's start
-- (the last ends at the hero's last snapshot). Per rep: input (on, or off for a control rep), the cast hero's last hits,
-- denies and deaths gained, HP-% lost (the sum of drops between 1 s snapshots, so a heal does not hide a hit), and the
-- forced context's own result lines inside the rep: `results` (ev=stack lines for drill `stack`) and `ok` (those with
-- res=stacked). A context with no join here reads its own lines over the rep window (`start`, `stop`).
-- ensure: ev_drill(ph, name, pid, team, pos, role, rep, input, start, forces)
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
rc AS (
    SELECT r.*, c.pid, c.pos, coalesce(r.next, (SELECT max(t) FROM sn WHERE sn.game_id = r.game_id AND sn.pid = c.pid)) AS stop
    FROM reps r JOIN cast c ON c.game_id = r.game_id AND c.team = r.team
)
SELECT rc.game_id, g.file, rc.name, rc.team, rc.pid, rc.pos, rc.rep, rc.input, rc.start, rc.stop, rc.forces,
    (SELECT max(lh) - min(lh) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.start AND sn.t <= rc.stop) AS lh,
    (SELECT max(dn) - min(dn) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.start AND sn.t <= rc.stop) AS dn,
    (SELECT max(deaths) - min(deaths) FROM sn WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t >= rc.start AND sn.t <= rc.stop) AS deaths,
    (SELECT coalesce(sum(CASE WHEN php > hp THEN php - hp ELSE 0 END), 0) FROM sn
        WHERE sn.game_id = rc.game_id AND sn.pid = rc.pid AND sn.t > rc.start AND sn.t <= rc.stop) AS hp_lost,
    CASE WHEN rc.forces = 'stack' THEN (SELECT count(*) FROM ev_stack s WHERE s.game_id = rc.game_id AND s.pid = rc.pid
        AND s.t >= rc.start AND s.t < rc.stop) END AS results,
    CASE WHEN rc.forces = 'stack' THEN (SELECT count(*) FROM ev_stack s WHERE s.game_id = rc.game_id AND s.pid = rc.pid
        AND s.t >= rc.start AND s.t < rc.stop AND s.res = 'stacked') END AS ok
FROM rc JOIN games g ON g.game_id = rc.game_id
ORDER BY rc.game_id, rc.team, rc.pid, rc.rep;
