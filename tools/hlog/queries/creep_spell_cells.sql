-- The spell read on their lane creeps, pooled per cell of hero, position, spell and creep kind (master
-- docs/proposals/2026-11-25-no-creep-unpaid.md s6): the stock shadow table that names which cells a cast to secure a creep is built for.
-- The rows, the join to the creep's death and the params are `q @creep_offers`'s (fragment creep_offer_rows); only `who=t` lines with a
-- spell answer (`sp`) count. A creep two heroes of ours were offered is a line of each, so cells of one lane share creeps.
-- Columns: hero, pos, sp, sx (u, p, n), ck, games (games the cell shows in), n (lines), kill (sk 1: a cast at some read kills), res (kill with
-- the reserve met: sr 0 or more), then the res lines by fate from the hero's team's view: us, nobody (a deny included), unm (no death joined); lost
-- (res and not us), and of those near (no walk: sg 0 or less), foe (an enemy hero also hit: sz above 0), key (a key spell:
-- sy k); sl, sd, sm (the lost lines' mean landing s, damage, mana), sa (their mean seconds from slot to the first killing read).
-- Params: as @creep_offers (like or batch required; from, until, back, fwd; comma lists ck, pid, hero).
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
cs AS (
    SELECT o.*, o.sk = 1 AND o.sr >= 0 AS res, o.sk = 1 AND o.sr >= 0 AND coalesce(o.paid, '') <> 'us' AS lost
    FROM creep_offer_rows o WHERE o.who = 't' AND o.sp IS NOT NULL
)
SELECT hero, pos, sp, sx, ck, count(DISTINCT game_id) AS games, count(*) AS n, coalesce(sum(sk = 1), 0) AS kill, coalesce(sum(res), 0) AS res,
    coalesce(sum(res AND paid = 'us'), 0) AS us, coalesce(sum(res AND paid = 'nobody'), 0) AS nobody,
    coalesce(sum(res AND NOT matched), 0) AS unm, coalesce(sum(lost), 0) AS lost,
    coalesce(sum(lost AND sg <= 0), 0) AS near, coalesce(sum(lost AND sz > 0), 0) AS foe, coalesce(sum(lost AND sy = 'k'), 0) AS key,
    round(avg(CASE WHEN lost THEN sl END), 2) AS sl, round(avg(CASE WHEN lost THEN sd END)) AS sd, round(avg(CASE WHEN lost THEN sm END)) AS sm,
    round(avg(CASE WHEN lost THEN sa END), 2) AS sa
FROM cs
GROUP BY hero, pos, sp, sx, ck
ORDER BY lost DESC, hero, sp, ck
