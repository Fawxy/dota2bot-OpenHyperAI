-- The heroes of one game and their snapshots in a window, for `hlog.js scene` (scene.js picks each frame's latest snapshot).
-- Params: game_id (games.game_id), lo and hi (seconds). One row per snapshot of each hero in [lo, hi]; a hero with none gives one
-- row with the snapshot columns NULL, so the roster is complete. Fast because the join filters on the store's (game_id, pid, t) index.
-- Row: pid, team, hero, pos (the last ev=bot line's; NULL for a human), t, seq, alive, hp (percent), x, y, mode, by, tgt, tid, ln, s, ld.
-- ensure: ev_bot(pid, team, pos, hero)
-- ensure: ev_player(pid, team, hero)
-- ensure: ev_snap(pid, alive, hp, x, y, mode, by, tgt, tid, ln, s, ld)
WITH who AS MATERIALIZED (
    SELECT pid, team, hero, pos FROM (
        SELECT pid, team, hero, pos, row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn FROM (
            SELECT pid, team, hero, pos, seq FROM ev_bot WHERE game_id = :game_id AND pid IS NOT NULL AND team IS NOT NULL
            UNION ALL
            SELECT pid, team, hero, NULL, seq FROM ev_player WHERE game_id = :game_id AND pid IS NOT NULL AND team IS NOT NULL
        )
    ) WHERE rn = 1
)
SELECT w.pid, w.team, w.hero, w.pos, s.t, s.seq, s.alive, s.hp, s.x, s.y, s.mode, s."by", s.tgt, s.tid, s.ln, s.s, s.ld
FROM who w
LEFT JOIN ev_snap s ON s.game_id = :game_id AND s.pid = w.pid AND s.t >= :lo AND s.t <= :hi
ORDER BY w.pid, s.t, s.seq
