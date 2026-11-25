-- The lane creep offer's lines counted per hero cell (master docs/proposals/2026-11-25-no-creep-unpaid.md s4a): one row per game, hero, creep
-- kind and whose creep it was. The rows, the join to the creep's death and the params are `q @creep_offers`'s (fragment creep_offer_rows).
-- Columns: file, game, label, lineup, arm, team, pid, hero, pos, ck, who, n (lines), n_in (in range: walk 0), n_wk (walk-ins: walk > 0), med_wk
-- (their median walk, s), covered (an enemy hero covers the stand spot), outdmg (the enemies' hit beats the creep's: ein > 0 and ed > md), atk
-- (the hero was attacking), mine (this hero took the creep: a last hit on theirs, a deny on ours), deny (the death was a deny, by either side: on
-- a `who=t` row their hero denied the creep, on a `who=o` row ours did, `mine` included; a deny pays nobody, so it is also in `nobody`); then the fate from the hero's team's view
-- as us, them, nobody, unm (no death joined), for all lines, and as in_* for the in-range ones and wk_* for the walk-ins; in_deny and wk_deny the denies of those.
-- Params: as @creep_offers (like or batch required; from, until, back, fwd; comma lists ck, who, pid, hero).
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
co_r AS (
    SELECT o.*, row_number() OVER (PARTITION BY o.game_id, o.pid, o.ck, o.who, o.walk > 0 ORDER BY o.walk, o.seq) AS wr,
        sum(o.walk > 0) OVER (PARTITION BY o.game_id, o.pid, o.ck, o.who) AS wn
    FROM creep_offer_rows o
),
co_md AS (
    SELECT game_id, pid, ck, who, round(avg(walk), 2) AS med_wk FROM co_r
    WHERE walk > 0 AND wr IN ((wn + 1) / 2, (wn + 2) / 2) GROUP BY game_id, pid, ck, who
)
SELECT gm.file, gm.game, gm.label, r.lineup, r.arm, o.team, o.pid, o.hero, o.pos, o.ck, o.who, count(*) AS n,
    coalesce(sum(o.inrange), 0) AS n_in, coalesce(sum(NOT o.inrange), 0) AS n_wk, max(m.med_wk) AS med_wk,
    coalesce(sum(o.covered), 0) AS covered, coalesce(sum(o.outdmg), 0) AS outdmg, coalesce(sum(o.atk), 0) AS atk, coalesce(sum(o.mine), 0) AS mine,
    coalesce(sum(o.how = 'deny'), 0) AS deny,
    coalesce(sum(o.paid = 'us'), 0) AS us, coalesce(sum(o.paid = 'them'), 0) AS them, coalesce(sum(o.paid = 'nobody'), 0) AS nobody, coalesce(sum(NOT o.matched), 0) AS unm,
    coalesce(sum(o.inrange AND o.paid = 'us'), 0) AS in_us, coalesce(sum(o.inrange AND o.paid = 'them'), 0) AS in_them, coalesce(sum(o.inrange AND o.paid = 'nobody'), 0) AS in_nobody,
    coalesce(sum(o.inrange AND NOT o.matched), 0) AS in_unm, coalesce(sum(o.inrange AND o.how = 'deny'), 0) AS in_deny,
    coalesce(sum(NOT o.inrange AND o.paid = 'us'), 0) AS wk_us, coalesce(sum(NOT o.inrange AND o.paid = 'them'), 0) AS wk_them, coalesce(sum(NOT o.inrange AND o.paid = 'nobody'), 0) AS wk_nobody,
    coalesce(sum(NOT o.inrange AND NOT o.matched), 0) AS wk_unm, coalesce(sum(NOT o.inrange AND o.how = 'deny'), 0) AS wk_deny
FROM co_r o JOIN gm USING (game_id)
LEFT JOIN run_label r USING (game_id)
LEFT JOIN co_md m ON m.game_id = o.game_id AND m.pid = o.pid AND m.ck = o.ck AND m.who = o.who
GROUP BY o.game_id, o.pid, o.ck, o.who
ORDER BY gm.file, gm.game, o.team, o.pid, o.ck, o.who
