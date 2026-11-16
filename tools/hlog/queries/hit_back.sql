-- D24h's judge (D24, "hit back when ... the exchange favours me"): its cases (fragment lane_rules: an unprovoked hit by one
-- hero in my reach, standing in our creep aggro) over the games matched, per side and role (mid pos 2, side pos 1 and 3,
-- sup pos 4 and 5): how many were answered (the hitter took hero damage within 4 s), the mean raw HP swing over 8 s
-- (`swing_*`: what I lost minus what the hitter lost; below 0 the exchange went my way) for answered and unanswered cases,
-- and deaths within 20 s (`died` mine, `hitter_died` the hitter's). Params: like, until (default 720), minhp (my HP % at the
-- onset, default 50; 70 reads the cores the way Ours.HitBack's bar does).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
x AS (SELECT 1)
SELECT (SELECT count(*) FROM lr_gl) AS games, side,
    CASE WHEN pos = 2 THEN 'mid' WHEN pos IN (1, 3) THEN 'side' ELSE 'sup' END AS role,
    count(*) AS n, sum(hb) AS answered,
    CAST(round(avg(CASE WHEN hb THEN my_lost - h_lost END)) AS INTEGER) AS swing_answered,
    CAST(round(avg(CASE WHEN NOT hb THEN my_lost - h_lost END)) AS INTEGER) AS swing_not,
    sum(my_died) AS died, sum(h_died) AS hitter_died
FROM lr_hbj
WHERE hp >= coalesce(:minhp, 50)
GROUP BY side, role
ORDER BY role, side
