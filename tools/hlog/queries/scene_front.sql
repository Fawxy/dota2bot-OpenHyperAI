-- Each team's lane fronts in a window, for `hlog.js scene`: every ev=front line with t in [lo, hi], oldest first.
-- Params: game_id (games.game_id), lo and hi (seconds). Amounts are absolute (0 at Radiant's ancient, see telemetry absAlong) and x, y the front's place.
-- Fast because ev_front is indexed on (game_id, t).
-- ensure: ev_front(team, top, topx, topy, mid, midx, midy, bot, botx, boty)
SELECT t, seq, team, top, topx, topy, mid, midx, midy, bot, botx, boty
FROM ev_front WHERE game_id = :game_id AND t >= :lo AND t <= :hi ORDER BY t, seq
