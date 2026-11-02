-- One row per rune trip or skip (ev=rune_job; slice rune-rotation). on_time: a started trip that reached its spot (the
-- verb's wait or channel label) by the spawn + 2 s (M.1's "arrives by the rune's spawn"; 2 s because the pick-up still
-- works and the verb's arrival carries a skill-scaled timing error). Skips have res=skip and no arrival. interrupted: as
-- slice 4's Amendment 1, B1's denominator leaves these out (rune_clean).
-- needs: ev_rune_job(pid, pos, kind, spawn, res, why, label, side, left, arr, away, died, hit, idle)
SELECT r.game_id, g.file, g.game, r.t, r.pid, r.pos, r.kind, r.spawn, r.res, r.why, r.label, r.side, r.left, r.arr, r.away,
    coalesce(r.died, 0) AS died,
    CASE WHEN r.res = 'skip' THEN 0 ELSE 1 END AS started,
    -- Another mode took the hero (retreat, Valve's attack, an exception) or the chooser ended it: not the trip's own execution.
    CASE WHEN r.res <> 'skip' AND (r.why LIKE 'preempted:mode=%' OR r.why LIKE 'cancelled:%') THEN 1 ELSE 0 END AS interrupted,
    CASE WHEN r.res <> 'skip' AND r.arr IS NOT NULL AND r.arr <= r.spawn + 2 THEN 1 ELSE 0 END AS on_time
FROM ev_rune_job r JOIN games g USING (game_id)
