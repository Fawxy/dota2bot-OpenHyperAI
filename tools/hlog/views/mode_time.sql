-- Seconds each hero spent in each mode, from ev=mode (dwell = seconds in `from` when the mode changed). The mode a hero
-- is still in at the end of the game has no ev=mode line, so its last stint is missing.
-- needs: ev_mode(pid, from, to, dwell)
SELECT g.file, g.game, m.pid, m."from" AS mode, sum(m.dwell) AS secs, count(*) AS stints
FROM ev_mode m JOIN games g USING (game_id)
GROUP BY m.game_id, m.pid, m."from"
