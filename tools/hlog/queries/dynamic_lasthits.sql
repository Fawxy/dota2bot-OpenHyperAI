-- Hero last hits before 10:00 for dynamic.js `ally_creep_steals` (part B, docs/team/slices/retire-dynamic-b.md): each ev=lasthit
-- (any unit) by a hero of the game alive at that whole second, with n (1 when absent or 0) and `near`, the comma-separated pids
-- of the same team's other heroes alive at that second within 700 units (`C.STEAL_R`). dynamicMetrics counts the rows of a
-- support (role 4-5) with a core (role 1-3) in `near`: roles stay in JS. Params: file (absolute log path), game (default 1).
-- ensure: ev_lasthit(pid, n)
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
lh AS (
    SELECT e.pid, e.t, e.n, e.seq FROM ev_lasthit e
    WHERE e.game_id = (SELECT game_id FROM gm) AND e.t < 600 AND e.pid IN (SELECT pid FROM hs_bot)
)
SELECT l.pid, l.t, CASE WHEN typeof(l.n) IN ('integer', 'real') AND l.n <> 0 THEN l.n ELSE 1 END AS n,
    (SELECT group_concat(o.pid) FROM hs_sec o
     WHERE o.team = me.team AND o.pid <> me.pid AND o.s = me.s AND o.alive IS NOT 0
       AND sqrt((o.x - me.x) * (o.x - me.x) + (o.y - me.y) * (o.y - me.y)) <= 700) AS near
FROM lh l JOIN hs_sec me ON me.pid = l.pid AND me.s = CAST(floor(l.t) AS INTEGER)
WHERE me.alive IS NOT 0
ORDER BY l.seq
