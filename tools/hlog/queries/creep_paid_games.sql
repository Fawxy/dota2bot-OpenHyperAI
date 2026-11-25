-- The lane creeps family's line per team-game (master docs/proposals/2026-11-25-no-creep-unpaid.md s3): of the lane creeps that died,
-- both sides', the share paid to the team, paid to the other team, and paid to nobody; and the counts under each. A row is a
-- game and team (fragment creep_paid_rows, read from that team's side); a group names its cell with the filters, every one read
-- the same way on both arms.
-- Columns: file, game, label, arm, side (`test` the label's seat, `opp` the other, NULL with no seat), team, n, us, them, nobody,
-- sh_us, sh_them, sh_nobody; then theirs (their creeps), t_lh (our last hits), t_dn (their denies), t_tower (under our tower,
-- no hero), t_other; ours (our creeps), o_lh (their last hits), o_dn (our denies), o_tower (under their tower), o_other.
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600);
-- each a comma list, unset for all: kind (melee, ranged, siege), lane (top, mid, bot, base, other), whose (theirs, ours), band
-- (the team's nearest hero: in, r150, r300, r1500, none), cband (its nearest pos 1-3 hero, the same bands; `none` for none).
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_paid_rows
cp_in AS (
    SELECT * FROM creep_paid_rows
    WHERE (:kind IS NULL OR instr(',' || :kind || ',', ',' || kind || ',') > 0)
        AND (:lane IS NULL OR instr(',' || :lane || ',', ',' || lane || ',') > 0)
        AND (:whose IS NULL OR instr(',' || :whose || ',', ',' || whose || ',') > 0)
        AND (:band IS NULL OR instr(',' || :band || ',', ',' || coalesce(band, '?') || ',') > 0)
        AND (:cband IS NULL OR instr(',' || :cband || ',', ',' || coalesce(cband, 'none') || ',') > 0)
),
cp_tm AS (SELECT game_id, team FROM gm CROSS JOIN (SELECT 2 AS team UNION ALL SELECT 3))
SELECT gm.file, gm.game, gm.label, r.arm,
    CASE WHEN r.seat_team IS NULL THEN NULL WHEN r.seat_team = m.team THEN 'test' ELSE 'opp' END AS side,
    m.team, count(p.uid) AS n,
    coalesce(sum(p.paid = 'us'), 0) AS us, coalesce(sum(p.paid = 'them'), 0) AS them, coalesce(sum(p.paid = 'nobody'), 0) AS nobody,
    round(avg(p.paid = 'us'), 3) AS sh_us, round(avg(p.paid = 'them'), 3) AS sh_them, round(avg(p.paid = 'nobody'), 3) AS sh_nobody,
    coalesce(sum(p.whose = 'theirs'), 0) AS theirs,
    coalesce(sum(p.whose = 'theirs' AND p.how = 'lh'), 0) AS t_lh, coalesce(sum(p.whose = 'theirs' AND p.how = 'deny'), 0) AS t_dn,
    coalesce(sum(p.whose = 'theirs' AND p.how = 'tower'), 0) AS t_tower, coalesce(sum(p.whose = 'theirs' AND p.how = 'other'), 0) AS t_other,
    coalesce(sum(p.whose = 'ours'), 0) AS ours,
    coalesce(sum(p.whose = 'ours' AND p.how = 'lh'), 0) AS o_lh, coalesce(sum(p.whose = 'ours' AND p.how = 'deny'), 0) AS o_dn,
    coalesce(sum(p.whose = 'ours' AND p.how = 'tower'), 0) AS o_tower, coalesce(sum(p.whose = 'ours' AND p.how = 'other'), 0) AS o_other
FROM cp_tm m JOIN gm USING (game_id)
LEFT JOIN cp_in p ON p.game_id = m.game_id AND p.team = m.team
LEFT JOIN run_label r ON r.game_id = m.game_id
GROUP BY m.game_id, m.team
ORDER BY gm.file, gm.game, m.team
