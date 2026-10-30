-- Every hero death of a game, oldest first (the rule is the fragment hero_death): team of the hero who died, t, n deaths at t.
-- Params: file (absolute log path, as in games.file), game (default 1). dynamic.js world metrics read it for the kill bursts.
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
-- include: hero_death
x AS (SELECT 1)
SELECT team, t, n FROM death ORDER BY t
