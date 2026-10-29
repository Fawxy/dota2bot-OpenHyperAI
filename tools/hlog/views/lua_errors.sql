-- Lua errors the humaniser caught, per game and call site (the H.1 standing check: 0 expected in our code).
-- n on the line is the repeat count at that moment, so max_n is the total the game logged for the site.
-- needs: ev_lua_error(where, n)
SELECT g.file, g.game, e."where" AS site, count(*) AS lines, max(e.n) AS max_n, min(e.t) AS first_t
FROM ev_lua_error e JOIN games g USING (game_id)
GROUP BY e.game_id, e."where"
