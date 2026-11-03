-- Which mode held lineup heroes, at what desire, and what they did while it did (eval-run "Targets": a miss blamed on another
-- mode is a cause only once the desire branch that fired is known). One row per mode, desire value and source, over snaps from
-- :from to :until. The desire value is the snap's `by` ("<mode> <desire> by <source>"), rounded to 0.01: a mode file's branches
-- return distinct values (OHA farm mode's X.ShouldRun returns BOT_MODE_DESIRE_ABSOLUTE * 1.1, so 1.10 there is a run, not
-- farming), so grep the mode file for the value to find the branch. Activity seconds from lane_activity: hero, creep, neutral,
-- building, idle (no recognised target: lane, retreat or other).
-- Params: like (LIKE pattern on games.file), from, until (seconds, default 90 and 600), pos_lo, pos_hi (lineup positions,
-- default 1-3, the cores), mode (one mode name, default all).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
h AS (
    SELECT a.game_id, a.mode, a.activity,
        CAST(substr(a.by, instr(a.by, ' ') + 1, instr(a.by, ' by ') - instr(a.by, ' ') - 1) AS REAL) AS desire,
        substr(a.by, instr(a.by, ' by ') + 4) AS src
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
      AND a.pos BETWEEN coalesce(:pos_lo, 1) AND coalesce(:pos_hi, 3)
      AND (:mode IS NULL OR a.mode = :mode)
      AND a.by LIKE a.mode || ' % by %'
)
SELECT mode, round(desire, 2) AS desire, src, count(*) AS secs, count(DISTINCT game_id) AS games,
    sum(activity = 'hero') AS hero, sum(activity = 'creep') AS creep, sum(activity = 'neutral') AS neutral,
    sum(activity = 'building') AS building, sum(activity IN ('lane', 'retreat', 'other')) AS idle
FROM h
GROUP BY mode, round(desire, 2), src
ORDER BY secs DESC
