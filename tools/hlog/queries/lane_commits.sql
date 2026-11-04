-- Lane fight commits (slice lane-fight): one row per game and role from `ev=trade kind=kill` (states/core_trade's commit), to
-- :until (default 600). offers (every kill line), taken (result kill or done), kills (result kill), lost (offered, never taken by
-- attack mode: the mode that held the hero is in `why`), deaths (the hero's death, dated at the snapshot before the dead gap,
-- between the commit's start, its line's t less dur, and 5 s after its line). Per commit: kill_rate = kills / taken,
-- death_rate = deaths / taken. :lf 1 (default) reads only commits under `Ours.CoreLaneFight` (`lf=1`), 0 only the others
-- (builds before the field read as 0).
-- Params: like (LIKE pattern on games.file), until, lf.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
k AS (
    SELECT tr.game_id, tr.t, tr.pid, tr.role, tr.result, tr.dur
    FROM ev_trade tr JOIN gm ON gm.game_id = tr.game_id
    WHERE tr.kind = 'kill' AND tr.t < coalesce(:until, 600)
      AND coalesce(tr.lf, 0) = coalesce(:lf, 1)
),
sn AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t, s.deaths FROM ev_snap s JOIN gm ON gm.game_id = s.game_id
    WHERE s.pid IN (SELECT pid FROM k WHERE k.game_id = s.game_id)
),
dd AS (
    SELECT game_id, pid, pt AS t FROM (
        SELECT *, lag(t) OVER w AS pt, lag(deaths) OVER w AS pd FROM sn WINDOW w AS (PARTITION BY game_id, pid ORDER BY t))
    WHERE deaths > pd AND t - pt > 2.5
)
SELECT gm.file, coalesce(k.role, 'core') AS role, count(*) AS offers,
    sum(k.result IN ('kill', 'done')) AS taken, sum(k.result = 'kill') AS kills, sum(k.result = 'lost') AS lost,
    sum(k.result IN ('kill', 'done') AND EXISTS (SELECT 1 FROM dd WHERE dd.game_id = k.game_id AND dd.pid = k.pid
        AND dd.t BETWEEN k.t - k.dur - 0.5 AND k.t + 5)) AS deaths
FROM k JOIN gm ON gm.game_id = k.game_id
GROUP BY gm.file, coalesce(k.role, 'core') ORDER BY gm.file, role
