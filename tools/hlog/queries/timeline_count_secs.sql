-- The hero seconds of a batch's games that `timeline <batch> --count` counts: per game and team, the live seconds in the window
-- of heroes at pos in the list pos (and in lane, when given): attacking an enemy hero (atk), of those in mode laning (atk_laning),
-- and within 700 of an enemy hero while in a lane (near700). A game with none of them has no row.
-- Params: batch (the exact run name), arm, from, to (seconds; from inclusive, to exclusive: 0:00 to 10:00 is 600 seconds), pos (comma separated), lane. Reads hero_sec as it is: fill it first (store.fillHeroSec).
-- The batch's games are picked first: joined the other way the planner scans every hero second of the store and parses a label for each.
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id, g.file, g.game
    FROM games g JOIN run_label r ON r.game_id = g.game_id
    WHERE r.batch = :batch AND (:arm IS NULL OR r.arm = :arm)
        AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)
)
SELECT g.file, g.game, h.team,
    sum(h.hits IS NOT NULL) AS atk,
    sum(h.hits IS NOT NULL AND h.mode = 'laning') AS atk_laning,
    sum(h.near <= 700 AND h.lane IN ('top', 'mid', 'bot')) AS near700
FROM gm g CROSS JOIN hero_sec h ON h.game_id = g.game_id
WHERE h.live AND h.sec >= :from AND h.sec < :to AND instr(',' || :pos || ',', ',' || h.pos || ',') > 0 AND (:lane IS NULL OR h.lane = :lane)
GROUP BY g.file, g.game, h.team
