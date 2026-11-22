-- One row per hero and whole second of a game, from the persisted hero_sec table (filled per game on first use from the episode fragments).
-- Columns: file, game, team, pos, hero, pid, sec, x, y, hp, mode, live, life (its deaths so far), lane (live seconds only: top, mid, bot, base, other),
-- hits (pid of the enemy hero it attacked that second), near (distance to the nearest live enemy hero), en900 and al900 (live enemy and allied heroes within 900).
-- Params: like (a path fragment or run label; required), game (default each log's last), pid, hero, lane, from and to (seconds).
-- For your own SQL read hero_sec (game_id, pid, sec are indexed) and join games; pass --p like (used in the SQL or not) to fill the games you read; with none, it reads what is filled and says so.
SELECT g.file, g.game, h.team, h.pos, h.hero, h.pid, h.sec, h.x, h.y, h.hp, h.mode, h.live, h.life, h.lane, h.hits, h.near, h.en900, h.al900
FROM games g JOIN hero_sec h ON h.game_id = g.game_id
WHERE g.file LIKE coalesce(:like, '')
    AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file))
    AND (:pid IS NULL OR h.pid = :pid) AND (:hero IS NULL OR h.hero = :hero) AND (:lane IS NULL OR h.lane = :lane)
    AND h.sec >= coalesce(:from, -1e9) AND h.sec <= coalesce(:to, 1e9)
ORDER BY g.file, h.sec, h.pid
