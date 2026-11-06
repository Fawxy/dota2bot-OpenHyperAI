-- Support idle in lane (slice lane-control 3, design s5.9 "idle"): how much of a bot support's laning time, 1:00-10:00, it
-- spends in the laning body's `hold` phase (ev=snap lf ph=hold: no last hit, deny, pre-deny, setup or other attempt), in
-- games whose file matches :like. One row per position (4, 5) plus `all`:
--   n supports (game and pid), snaps laning snapshots, hold_share the share of them in ph=hold, laning_share the share of
--   all its snapshots 1:00-10:00 in mode laning (time in lane against time on jobs, walking, retreat).
-- A snapshot is one ev=snap line (the same cadence for every hero), so shares are of time.
-- ensure: ev_snap(pid, mode, lf)
-- ensure: ev_bot(pid, pos)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
sp AS MATERIALIZED (
    SELECT b.game_id, b.pid, max(b.pos) AS pos FROM ev_bot b JOIN gm ON gm.game_id = b.game_id
    WHERE b.pos IN (4, 5) GROUP BY 1, 2
),
s AS MATERIALIZED (
    SELECT sp.pos, sp.game_id, sp.pid,
        sum(s.mode = 'laning') AS lan,
        sum(s.mode = 'laning' AND s.lf LIKE 'ph=hold%') AS hold,
        count(*) AS n
    FROM sp JOIN ev_snap s ON s.game_id = sp.game_id AND s.pid = sp.pid
    WHERE s.t >= 60 AND s.t < 600
    GROUP BY 1, 2, 3
)
SELECT pos, count(*) AS n, sum(lan) AS snaps,
    round(1.0 * sum(hold) / max(1, sum(lan)), 2) AS hold_share,
    round(1.0 * sum(lan) / max(1, sum(n)), 2) AS laning_share
FROM (SELECT pos, lan, hold, n FROM s UNION ALL SELECT 'all', lan, hold, n FROM s)
GROUP BY pos ORDER BY pos = 'all', pos;
