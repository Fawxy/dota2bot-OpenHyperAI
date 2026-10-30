-- Guard-rail counts for the L.1 creep-economy share (GOALS.md L.1), per game and team at 10:00 (last ev=snap of each hero at t < 600,
-- the window creep_share uses).
-- team_lh, team_dn: last hits and denies of the team's heroes; core_lh, core_dn: the lineup pos 1-3 heroes only; deaths: hero deaths,
-- plus one for a hero whose last snapshot is over 2.5 s before 10:00 while the game ran past it (bots log no snapshot while dead, so
-- its counter has not risen yet: dynamic.js C.DEAD_GAP);
-- not_in_share = (team_lh + team_dn) - (creep_share taken), a net figure: counter rises with no matching logged lane-creep death
-- (neutral and jungle kills, one-frame kills the 50% health rule drops, creeps further than 1,500 from every hero), reported per arm.
-- It is NULL when creep_share has no row for the team (a log from before 406ee95, or no creeps logged).
-- Audited steals are the named query @steals (H.2), not repeated here. A hero's team is its last ev=bot or ev=player line's.
-- Heroes without a lineup position (a human) count in the team columns, not in the core columns.
-- needs: ev_snap(pid, lh, dn, deaths)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_player(pid, team, hero)
WITH who AS (
    SELECT game_id, pid, team, row_number() OVER (PARTITION BY game_id, pid ORDER BY seq DESC) AS rn
    FROM (SELECT game_id, pid, team, seq FROM ev_bot WHERE pid IS NOT NULL AND team IS NOT NULL
          UNION ALL SELECT game_id, pid, team, seq FROM ev_player WHERE pid IS NOT NULL AND team IS NOT NULL)
),
gend AS (
    SELECT game_id, max(t) AS tmax FROM ev_snap GROUP BY game_id
),
last AS (
    SELECT game_id, pid, t, lh, dn, deaths,
        row_number() OVER (PARTITION BY game_id, pid ORDER BY t DESC, seq DESC) AS rn
    FROM ev_snap WHERE t < 600 AND x IS NOT NULL AND lh IS NOT NULL
),
h AS (
    SELECT l.game_id, w.team, l.pid, l.lh, l.dn,
        l.deaths + CASE WHEN 600 - l.t > 2.5 AND (SELECT tmax FROM gend e WHERE e.game_id = l.game_id) >= 600 THEN 1 ELSE 0 END AS deaths,
        coalesce((SELECT n.pos BETWEEN 1 AND 3 FROM lineup n WHERE n.game_id = l.game_id AND n.pid = l.pid), 0) AS core
    FROM last l JOIN who w ON w.game_id = l.game_id AND w.pid = l.pid AND w.rn = 1
    WHERE l.rn = 1
)
SELECT h.game_id, h.team,
    sum(h.lh) AS team_lh, sum(h.dn) AS team_dn,
    sum(CASE WHEN h.core THEN h.lh ELSE 0 END) AS core_lh, sum(CASE WHEN h.core THEN h.dn ELSE 0 END) AS core_dn,
    sum(h.deaths) AS deaths,
    CASE WHEN s.taken IS NULL THEN NULL ELSE sum(h.lh) + sum(h.dn) - s.taken END AS not_in_share
FROM h LEFT JOIN creep_share s ON s.game_id = h.game_id AND s.team = h.team
GROUP BY h.game_id, h.team
