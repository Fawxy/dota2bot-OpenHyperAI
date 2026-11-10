-- The head-to-head farm readout from our own telemetry (no replay needed): per game and team, from each hero's last
-- snapshot at or before :at, the team's net worth (`nw`, GetNetWorth), last hits, denies, kills, deaths and mean level, and
-- the cores' (pos 1-3) last hits. Net worth is NULL for a team with a hero that logged none (builds before `nw`).
-- Params: like, at (default 600).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
who AS MATERIALIZED (
    SELECT game_id, pid, team, pos, CASE WHEN instr(coalesce(ours, ''), ':1') > 0 THEN 'ours' ELSE 'oha' END AS side
    FROM (
        SELECT b.game_id, b.pid, b.team, b.pos, b.ours, row_number() OVER (PARTITION BY b.game_id, b.pid ORDER BY b.seq DESC) AS rn
        FROM ev_bot b JOIN gm ON gm.game_id = b.game_id WHERE b.team IS NOT NULL AND b.pos IS NOT NULL
    ) WHERE rn = 1
),
lt AS (
    SELECT w.*, (SELECT max(s.t) FROM ev_snap s WHERE s.game_id = w.game_id AND s.pid = w.pid AND s.t <= coalesce(:at, 600)) AS t
    FROM who w
),
h AS (
    SELECT lt.game_id, lt.team, lt.side, lt.pos, s.nw, s.lh, s.dn, s.kills, s.deaths, s.lvl
    FROM lt JOIN ev_snap s ON s.game_id = lt.game_id AND s.pid = lt.pid AND s.t = lt.t
    GROUP BY lt.game_id, lt.pid
)
SELECT gm.file, h.side, h.team,
    CASE WHEN count(h.nw) = count(*) THEN CAST(sum(h.nw) AS INTEGER) END AS nw,
    sum(coalesce(h.lh, 0)) AS lh, sum(coalesce(h.dn, 0)) AS dn,
    sum(coalesce(h.kills, 0)) AS kills, sum(coalesce(h.deaths, 0)) AS deaths,
    round(avg(h.lvl), 1) AS lvl,
    sum(CASE WHEN h.pos <= 3 THEN coalesce(h.lh, 0) ELSE 0 END) AS core_lh
FROM h JOIN gm ON gm.game_id = h.game_id
GROUP BY h.game_id, h.team
ORDER BY gm.file, h.team
