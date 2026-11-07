-- Drills: did the harness hold? One row per hero of each drill game whose file matches :like: its role (the last
-- `ev=drill ph=role`), its snapshots from 0:00, how many had an attack target (`tgt`; a bench or statue should have none),
-- the share in farm mode (where a drill holds bench and statue), its deaths, and its mean position (a bench at its fountain,
-- a statue in its lane).
-- ensure: ev_drill(ph, name, pid, team, pos, role, rep, input, start, forces)
WITH
gm AS MATERIALIZED (
    SELECT DISTINCT d.game_id FROM ev_drill d JOIN games g ON g.game_id = d.game_id
    WHERE d.ph = 'role' AND g.file LIKE coalesce(:like, '%')
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
    round(avg(s.x)) AS x, round(avg(s.y)) AS y
FROM r JOIN games g ON g.game_id = r.game_id
LEFT JOIN ev_snap s ON s.game_id = r.game_id AND s.pid = r.pid AND s.t >= 0
GROUP BY r.game_id, r.pid
ORDER BY r.game_id, r.team, r.pid;
