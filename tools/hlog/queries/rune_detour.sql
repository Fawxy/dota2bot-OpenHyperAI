-- The rune detour's audit (doctrine D23, rune_detour.ts; plan s5's small row): one row per pass the row (or its shadow) read,
-- `ev=choice kind=rune_detour`, with the walk it started and whether the hero took the rune.
--   go, want, why, src, ex (the smallest detour read, s), dr (its distance to the rune), slot (the spawn)
--   job_t, job_why   the walk's `ev=job job=rune_detour phase=end` line after the start (go=1 only): `ok` on a pickup
--   secs             the walk's seconds, start to end (the hold's cost; the cap is the walk's predicted seconds plus 4)
--   took             1 when this hero's own ev=rune_pickup on the rune falls from the start to the walk's end + 2
-- Params: like (a path fragment or run label; required).
-- ensure: ev_choice(pid, kind, go, want, why, src, slot, rune, ex, dr)
-- ensure: ev_job(pid, job, phase, why, ex)
-- ensure: ev_rune_pickup(pid, team, rune, kind)
WITH
gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '') AND bots > 0),
c AS MATERIALIZED (
    SELECT c.game_id, c.t, c.pid, c.go, c.want, c.why, c.src, c.slot, c.rune, c.ex, c.dr
    FROM ev_choice c JOIN gm USING (game_id) WHERE c.kind = 'rune_detour'
),
j AS (
    SELECT c.*, (SELECT min(e.t) FROM ev_job e WHERE e.game_id = c.game_id AND e.pid = c.pid AND e.job = 'rune_detour'
        AND e.phase = 'end' AND e.t >= c.t AND e.t <= c.t + 60) AS job_t
    FROM c
)
SELECT gm.file, gm.game, j.pid, j.t, j.slot, j.src, j.go, j.want, j.why, j.ex, j.dr, j.job_t,
    (SELECT e.why FROM ev_job e WHERE e.game_id = j.game_id AND e.pid = j.pid AND e.job = 'rune_detour' AND e.phase = 'end'
        AND e.t = j.job_t LIMIT 1) AS job_why,
    round(j.job_t - j.t, 1) AS secs,
    CASE WHEN j.go = 1 THEN (SELECT count(*) > 0 FROM ev_rune_pickup p WHERE p.game_id = j.game_id AND p.pid = j.pid
        AND p.rune = j.rune AND p.t >= j.t AND p.t <= coalesce(j.job_t, j.t + 30) + 2) END AS took
FROM j JOIN gm USING (game_id)
ORDER BY gm.file, gm.game, j.t, j.pid
