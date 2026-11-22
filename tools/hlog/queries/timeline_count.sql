-- The episodes of a batch's games that `timeline <batch> --count` counts: one row per death, retreat, exchange or kill_try of a game that has a seat, with its side (test or opp), its hero's pos and, for a kill_try, the target's pos (tpos).
-- The rows are those of timeline_rows (an episode in the window when any part of it is). The counting is summary.js.
-- Params: batch (the exact run name), arm, from, to (seconds), lane; like, game, hero, pid, kind are timeline_rows' own, pass them as null.
WITH
-- include: timeline_rows
tc AS (
    SELECT r.file, r.game, r.arm, r.side, r.kind, r.pos, r.t, r.t1, r.outcome,
        (SELECT w.pos FROM ep_who w JOIN gm ON gm.game_id = w.game_id WHERE gm.file = r.file AND gm.game = r.game AND w.pid = r.other_pid) AS tpos
    FROM timeline_rows r WHERE r.side IS NOT NULL AND r.kind IN ('death', 'retreat', 'exchange', 'kill_try')
)
SELECT * FROM tc ORDER BY file, t
