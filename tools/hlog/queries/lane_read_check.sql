-- How well the lane read agrees with what the game did, one row per lane (slice lane-read; rows from the view lane_read_check).
-- Params: like (LIKE pattern on games.file, default every game), from and until (seconds, default 90 and 600).
-- C1 creep advantage: n1 readings, adv_mae mean |adv - adv_true|, adv_02 share within 0.2, fogged share with fewer enemy creeps
--   seen near our front than were there.
-- C2 meeting point: n2 readings with creeps on both sides, eq_mae mean |eq - eq_true|.
-- C3 outcome: n3 readings with adv off 1 by 0.2 or more and a 10 s window before the next spawn where the two sides lost
--   different creep HP; agree share where the side adv favoured lost less.
-- C4 punish: n4 (second, missing enemy) pairs, an alive enemy hero the reading lists as not visible; near4 of them truly within
--   2,000 of our front (ev=snap position); recall4 share of those the reading's last-seen spot also put within 2,000;
--   precision4 share of the reading's within-2,000 that truly were.
-- ensure: ev_snap(pid, x, y, alive)
WITH gm AS MATERIALIZED (
    SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')
),
c AS (
    SELECT v.* FROM lane_read_check v JOIN gm ON gm.game_id = v.game_id
    WHERE v.sec BETWEEN coalesce(:from, 90) AND coalesce(:until, 600)
),
tok(game_id, sec, lane, fx, fy, rest, item) AS (
    SELECT game_id, sec, lane, fx, fy, ee || ';', NULL FROM c WHERE ee IS NOT NULL AND ee <> ''
    UNION ALL
    SELECT game_id, sec, lane, fx, fy, substr(rest, instr(rest, ';') + 1), substr(rest, 1, instr(rest, ';') - 1)
    FROM tok WHERE rest <> ''
),
parts AS (
    SELECT game_id, sec, lane, fx, fy,
        CAST(substr(item, 1, instr(item, ':') - 1) AS INTEGER) AS pid,
        substr(item, instr(item, ':') + 1) AS r2
    FROM tok WHERE item IS NOT NULL AND item <> ''
),
missing AS (
    SELECT p.game_id, p.sec, p.lane, p.fx, p.fy, p.pid,
        CAST(substr(p.r2, instr(p.r2, ':') + 1) AS REAL) AS read_dist
    FROM parts p WHERE substr(p.r2, 1, 1) <> 'v'
),
snaps AS (
    SELECT game_id, CAST(t AS INTEGER) AS sec, pid, min(seq) AS seq FROM ev_snap GROUP BY 1, 2, 3
),
m AS (
    SELECT m.lane, m.read_dist <= 2000 AS read_near,
        (s.x - m.fx) * (s.x - m.fx) + (s.y - m.fy) * (s.y - m.fy) <= 2000 * 2000 AS true_near
    FROM missing m
    JOIN snaps k ON k.game_id = m.game_id AND k.sec = m.sec AND k.pid = m.pid
    JOIN ev_snap s ON s.game_id = k.game_id AND s.seq = k.seq
    WHERE s.alive IS NOT 0
),
m4 AS (
    SELECT lane, count(*) AS n4, sum(true_near) AS near4,
        round(avg(CASE WHEN true_near THEN read_near END), 3) AS recall4,
        round(avg(CASE WHEN read_near THEN true_near END), 3) AS precision4
    FROM m GROUP BY lane
)
SELECT c.lane, count(*) AS n1,
    round(avg(abs(c.adv - c.adv_true)), 3) AS adv_mae,
    round(avg(abs(c.adv - c.adv_true) <= 0.2), 3) AS adv_02,
    round(avg(c.e_seen < c.e_true), 3) AS fogged,
    count(c.eq_true) AS n2,
    round(avg(abs(c.eq - c.eq_true)), 3) AS eq_mae,
    sum(abs(c.adv - 1) >= 0.2 AND c.hp_lost IS NOT NULL AND c.ehp_lost IS NOT NULL AND c.hp_lost <> c.ehp_lost) AS n3,
    round(avg(CASE WHEN abs(c.adv - 1) >= 0.2 AND c.hp_lost IS NOT NULL AND c.ehp_lost IS NOT NULL AND c.hp_lost <> c.ehp_lost
        THEN (c.adv > 1) = (c.ehp_lost > c.hp_lost) END), 3) AS agree3,
    m4.n4, m4.near4, m4.recall4, m4.precision4
FROM c LEFT JOIN m4 ON m4.lane = c.lane
GROUP BY c.lane
ORDER BY c.lane
