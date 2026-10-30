-- Guard-rail counts for the L.1 creep-economy share (GOALS.md L.1), per game and team at 10:00 (last ev=snap of each hero at t <= 600).
-- team_lh, team_dn: last hits and denies of the team's heroes; core_lh, core_dn: the lineup pos 1-3 heroes only; deaths: hero deaths;
-- not_in_share = (team_lh + team_dn) - (creep_share taken): counter rises with no matching logged lane-creep death (neutral and
-- jungle kills, one-frame kills the 50% health rule drops, creeps further than 1,500 from every hero), reported per arm.
-- Audited steals are the named query @steals (H.2), not repeated here. Team = pid < 5 radiant (2), else dire (3), as the snap pids go.
-- Heroes without a lineup position (a human) count in the team columns, not in the core columns.
-- needs: ev_snap(pid, lh, dn, deaths)
-- ensure: ev_bot(pid, team, pos)
WITH last AS (
    SELECT game_id, pid, lh, dn, deaths,
        row_number() OVER (PARTITION BY game_id, pid ORDER BY t DESC, seq DESC) AS rn
    FROM ev_snap WHERE t <= 600 AND x IS NOT NULL AND lh IS NOT NULL
),
h AS (
    SELECT l.game_id, CASE WHEN l.pid < 5 THEN 2 ELSE 3 END AS team, l.pid, l.lh, l.dn, l.deaths,
        coalesce((SELECT n.pos BETWEEN 1 AND 3 FROM lineup n WHERE n.game_id = l.game_id AND n.pid = l.pid), 0) AS core
    FROM last l WHERE l.rn = 1
)
SELECT h.game_id, h.team,
    sum(h.lh) AS team_lh, sum(h.dn) AS team_dn,
    sum(CASE WHEN h.core THEN h.lh ELSE 0 END) AS core_lh, sum(CASE WHEN h.core THEN h.dn ELSE 0 END) AS core_dn,
    sum(h.deaths) AS deaths,
    sum(h.lh) + sum(h.dn) - coalesce(s.taken, 0) AS not_in_share
FROM h LEFT JOIN creep_share s ON CAST(s.game_id AS INTEGER) = CAST(h.game_id AS INTEGER) AND s.team = h.team
GROUP BY h.game_id, h.team
