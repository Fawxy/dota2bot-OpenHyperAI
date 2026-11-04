-- The team's 6:00 power rune (slice rune-spawn): one row per game and team that made a plan (`ev=rune_plan`).
--   mid, sup     the planned heroes (null: the plan's `why`, no-mid / no-free-support; not selected, the column exists only when a
--                game logged one)
--   trips        6:00 power trips of the planned heroes that started (`ev=rune_job` kind=power spawn=360, res not skip)
--   covered      1 when every planned hero reached its spot by the spawn + 1 s (`arr`), the plan's coverage
--   take, take_ok, deny, deny_ok, off, cross, cross_ok, none   the act at the spawn (`phase`) and its ok results
--   late         trips that never reached the spot (`why` timeout:late), dead (died=1), hid (mean seconds hidden at the stand)
-- Params: like.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
pl AS (SELECT p.game_id, p.team, p.mid, p.sup FROM ev_rune_plan p JOIN gm ON gm.game_id = p.game_id),
tr AS (
    SELECT j.game_id, pl.team, j.pid, j.res, j.why, j.phase, j.arr, j.died, j.hid
    FROM ev_rune_job j JOIN pl ON pl.game_id = j.game_id AND (j.pid = pl.mid OR j.pid = pl.sup)
    WHERE j.kind = 'power' AND j.spawn = 360 AND j.res <> 'skip'
)
SELECT pl.game_id, pl.team, pl.mid, pl.sup,
    count(tr.pid) AS trips,
    CASE WHEN count(tr.pid) = (pl.mid IS NOT NULL) + (pl.sup IS NOT NULL)
        AND sum(CASE WHEN tr.arr IS NOT NULL AND tr.arr <= 361 THEN 1 ELSE 0 END) = count(tr.pid) THEN 1 ELSE 0 END AS covered,
    total(tr.phase = 'take') AS take, total(tr.phase = 'take' AND tr.res = 'ok') AS take_ok,
    total(tr.phase = 'deny') AS deny, total(tr.phase = 'deny' AND tr.res = 'ok') AS deny_ok,
    total(tr.phase = 'off') AS off, total(tr.phase = 'cross') AS cross, total(tr.phase = 'cross' AND tr.res = 'ok') AS cross_ok,
    total(tr.phase = 'none') AS none,
    total(tr.why = 'timeout:late') AS late, total(tr.died = 1) AS dead, round(avg(tr.hid), 1) AS hid
FROM pl LEFT JOIN tr ON tr.game_id = pl.game_id AND tr.team = pl.team
GROUP BY pl.game_id, pl.team
ORDER BY pl.game_id, pl.team;
