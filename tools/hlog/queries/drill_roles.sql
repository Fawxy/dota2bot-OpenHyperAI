-- Drills: did the harness hold? One row per hero of each drill game whose file matches :like: its role (the last
-- `ev=drill ph=role`), its snapshots from 0:00, how many had an attack target (`tgt`; a bench or statue should have none),
-- the share in farm mode (where a drill holds bench and statue), its deaths, and its mean position (a bench at its fountain,
-- a statue in its lane). For a rig's cast (slice drill-rig), `rel_modes`: the distinct snapshot modes from each ready line
-- (`ok=1`) to the next rep's start, so a mode outside the entry's release list shows here.
-- ensure: ev_drill(ph, name, pid, team, pos, role, rep, input, start, forces, ok)
WITH
gm AS MATERIALIZED (
    SELECT DISTINCT d.game_id FROM ev_drill d JOIN games g ON g.game_id = d.game_id
    WHERE d.ph = 'role' AND g.file LIKE coalesce(:like, '%')
),
win AS MATERIALIZED (
    SELECT d.game_id, d.pid, d.t AS t0,
        coalesce((SELECT min(n.t) FROM ev_drill n WHERE n.game_id = d.game_id AND n.ph = 'rep' AND n.t > d.t), 1e9) AS t1
    FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'ready' AND d.ok = 1
),
rel AS MATERIALIZED (
    SELECT w.game_id, w.pid, group_concat(DISTINCT s.mode) AS rel_modes
    FROM win w JOIN ev_snap s ON s.game_id = w.game_id AND s.pid = w.pid AND s.t > w.t0 AND s.t < w.t1
    GROUP BY w.game_id, w.pid
),
r AS MATERIALIZED (
    SELECT game_id, pid, team, pos, role, name FROM (
        SELECT d.*, row_number() OVER (PARTITION BY d.game_id, d.pid ORDER BY d.seq DESC) AS rn
        FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'role'
    ) WHERE rn = 1
)
SELECT r.game_id, g.file, r.name, r.team, r.pid, r.pos, r.role,
    count(s.t) AS snaps,
    sum(s.tgt IS NOT NULL AND s.tgt <> '') AS tgt,
    round(1.0 * sum(s.mode = 'farm') / max(count(s.t), 1), 2) AS farm,
    max(s.deaths) AS deaths,
    round(avg(s.x)) AS x, round(avg(s.y)) AS y,
    (SELECT rel_modes FROM rel WHERE rel.game_id = r.game_id AND rel.pid = r.pid) AS rel_modes
FROM r JOIN games g ON g.game_id = r.game_id
LEFT JOIN ev_snap s ON s.game_id = r.game_id AND s.pid = r.pid AND s.t >= 0
GROUP BY r.game_id, r.pid
ORDER BY r.game_id, r.team, r.pid;
