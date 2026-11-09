-- One row per D1, D2, D3, D7 or D9 situation found in a game, with whether it was a violation and its cause (fragment
-- lane_rules has the rules). Params: like, until (default 720), rule (one id, default all), all (1 lists the situations that
-- were not violations too; default violations only).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
x AS (SELECT 1)
SELECT gm.file, c.rule, c.side, c.team, c.pos, c.pid, c.t, c.viol, c.cause, c.hp, c.en, c.al, c.secs, c.mode
FROM lr_case c JOIN gm ON gm.game_id = c.game_id
WHERE (:rule IS NULL OR c.rule = :rule) AND (coalesce(:all, 0) = 1 OR c.viol)
ORDER BY gm.file, c.rule, c.t
