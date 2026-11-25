-- How often a support (pos 4-5) has an "orphan" last hit, a deny chance, and the two at once (sizing for a support-deny rule that
-- ranks an orphan last hit over a deny). Side lanes only; reads fragment creep_paid_rows from each team's side.
--   orphan       one of THEIR ranged creeps (whose theirs, kind ranged) with the team's nearest pos 4-5 hero in reach (sband in or
--                r150) and no pos 1-3 hero in reach (cband not in or r150; none within 1,500 counts as not in reach).
--   deny chance  one of OUR creeps, any kind (whose ours), with that support in reach (sband in or r150).
--   clash        an orphan with a deny chance for the same support (spid) within `win` seconds either side; `dclash` the same counted
--                from the deny chances (a deny chance with an orphan within `win`).
-- Columns: file, game, label, arm, side (`test` the label's seat, `opp` the other, NULL with no seat), team, then orph, orph_sup (paid
-- us, by_pid the support in reach), orph_core (paid us by any other hero), orph_dn (their hero denied it), orph_unpaid (paid nobody, not a deny); dch, dch_sup (denied by the
-- support), dch_core (denied by any other hero of ours), dch_them (their last hit), dch_other (tower, a death nobody logged a hero on,
-- a deny with no by_pid); clash, dclash. With :sum = 1 one row per arm and side instead: `tg` team-games, then the same counts as
-- means per team-game (`m_` prefix) and `s_clash`, `s_dclash` the totals.
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600);
-- win (seconds, default 2); sum (0 or 1).
-- Caveats: a support's reach is estimated from snapshots (exact 0, never measured): it reads a hero in range about one time in ten
-- too seldom, so every count here is a floor, and the cband test is measured for cores on their creeps only. The row's support is the
-- nearest pos 4-5 hero within 1,500 at the death, not necessarily the one that would act. Stock (OHA) supports in both arms of the
-- batches read so far, so this sizes what stock supports face and do. A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_paid_rows
so_o AS (
    SELECT game_id, team, spid, t, how, paid, by_pid FROM creep_paid_rows
    WHERE lane IN ('top', 'bot') AND whose = 'theirs' AND kind = 'ranged' AND sband IN ('in', 'r150')
        AND coalesce(cband, 'none') NOT IN ('in', 'r150')
),
so_d AS (
    SELECT game_id, team, spid, t, how, paid, by_pid FROM creep_paid_rows
    WHERE lane IN ('top', 'bot') AND whose = 'ours' AND sband IN ('in', 'r150')
),
so_tm AS (SELECT game_id, team FROM gm CROSS JOIN (SELECT 2 AS team UNION ALL SELECT 3)),
so_row AS (
    SELECT gm.file, gm.game, gm.label, r.arm,
        CASE WHEN r.seat_team IS NULL THEN NULL WHEN r.seat_team = m.team THEN 'test' ELSE 'opp' END AS side, m.team,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team) AS orph,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team AND o.paid = 'us' AND o.by_pid = o.spid) AS orph_sup,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team AND o.paid = 'us' AND o.by_pid <> o.spid) AS orph_core,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team AND o.how = 'deny') AS orph_dn,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team AND o.paid = 'nobody' AND o.how <> 'deny') AS orph_unpaid,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team) AS dch,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team AND d.how = 'deny' AND d.by_pid = d.spid) AS dch_sup,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team AND d.how = 'deny' AND d.by_pid <> d.spid) AS dch_core,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team AND d.paid = 'them') AS dch_them,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team AND d.paid <> 'them'
            AND NOT (d.how = 'deny' AND d.by_pid IS NOT NULL)) AS dch_other,
        (SELECT count(*) FROM so_o o WHERE o.game_id = m.game_id AND o.team = m.team AND EXISTS (SELECT 1 FROM so_d d
            WHERE d.game_id = o.game_id AND d.team = o.team AND d.spid = o.spid AND abs(d.t - o.t) <= coalesce(:win, 2))) AS clash,
        (SELECT count(*) FROM so_d d WHERE d.game_id = m.game_id AND d.team = m.team AND EXISTS (SELECT 1 FROM so_o o
            WHERE o.game_id = d.game_id AND o.team = d.team AND o.spid = d.spid AND abs(d.t - o.t) <= coalesce(:win, 2))) AS dclash
    FROM so_tm m JOIN gm USING (game_id) LEFT JOIN run_label r ON r.game_id = m.game_id
)
SELECT file, game, label, arm, side, team, orph, orph_sup, orph_core, orph_dn, orph_unpaid, dch, dch_sup, dch_core, dch_them, dch_other,
    clash, dclash, NULL AS tg, NULL AS m_orph, NULL AS m_orph_sup, NULL AS m_orph_core, NULL AS m_orph_dn, NULL AS m_orph_unpaid,
    NULL AS m_dch, NULL AS m_dch_sup, NULL AS m_dch_core, NULL AS m_dch_them, NULL AS m_dch_other, NULL AS m_clash, NULL AS m_dclash,
    NULL AS s_clash, NULL AS s_dclash
FROM so_row WHERE coalesce(:sum, 0) = 0
UNION ALL
SELECT NULL, NULL, NULL, arm, side, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, count(*),
    round(avg(orph), 3), round(avg(orph_sup), 3), round(avg(orph_core), 3), round(avg(orph_dn), 3), round(avg(orph_unpaid), 3),
    round(avg(dch), 3), round(avg(dch_sup), 3), round(avg(dch_core), 3), round(avg(dch_them), 3), round(avg(dch_other), 3),
    round(avg(clash), 3), round(avg(dclash), 3), sum(clash), sum(dclash)
FROM so_row WHERE coalesce(:sum, 0) = 1 GROUP BY arm, side
ORDER BY 1, 2, 6
