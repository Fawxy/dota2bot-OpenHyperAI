-- The lane creeps family's rows (master docs/proposals/2026-11-25-no-creep-unpaid.md s3): one row per lane creep death and team, who
-- was paid for it and that team's reach at the death. The unit, fates and reach are the fragment creep_paid_rows's; per team-game:
-- `q @creep_paid_games`.
-- Columns: file, game, label, arm, side (`test` when the row's team is the label's seat, `opp` the other, NULL with no seat), t, uid (unit_life's: `q @unit --p uid=`), team,
-- whose, kind, lane, how, paid, by_pid, tw, pid, pos, hero, hln, dist, ar, gap, band, hp, atk, ed, busy, cpid, cgap, cband.
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600).
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_paid_rows
cp_who AS (SELECT game_id, pid, max(hero) AS hero FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY game_id, pid)
SELECT gm.file, gm.game, gm.label, r.arm,
    CASE WHEN r.seat_team IS NULL THEN NULL WHEN r.seat_team = p.team THEN 'test' ELSE 'opp' END AS side,
    p.t, p.uid, p.team, p.whose, p.kind, p.lane, p.how, p.paid, p.by_pid, p.tw, p.pid, p.pos, w.hero, p.hln, p.dist, p.ar, p.gap, p.band,
    p.hp, p.atk, p.ed, p.busy, p.cpid, p.cgap, p.cband
FROM creep_paid_rows p JOIN gm USING (game_id)
LEFT JOIN run_label r USING (game_id)
LEFT JOIN cp_who w ON w.game_id = p.game_id AND w.pid = p.pid
ORDER BY gm.file, gm.game, p.t, p.team, p.uid
