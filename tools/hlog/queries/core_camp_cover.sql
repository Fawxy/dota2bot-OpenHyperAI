-- Core camp coverage (slice core-next-gold): wave windows (`win`, the forecast clash second / 30) where a camp fitted and a
-- gate held the trip (`ev=core_camp phase=skip`) and no trip started in that window, by the first skip's `why`, in games
-- whose file matches :like. `windows` counts (game, pid, win); `trips` the windows with a start, for the share.
-- ensure: ev_core_camp(pid, phase, win, why)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
c AS (SELECT c.* FROM ev_core_camp c JOIN gm ON gm.game_id = c.game_id WHERE c.phase IN ('start', 'skip')),
w AS (
    SELECT game_id, pid, win, max(phase = 'start') AS started,
        (SELECT c2.why FROM c c2 WHERE c2.game_id = c.game_id AND c2.pid = c.pid AND c2.win = c.win AND c2.phase = 'skip' ORDER BY c2.t LIMIT 1) AS why
    FROM c GROUP BY game_id, pid, win
)
SELECT coalesce(why, '-') AS why, count(*) AS windows, sum(started) AS trips, sum(started = 0) AS missed
FROM w GROUP BY 1 ORDER BY missed DESC;
