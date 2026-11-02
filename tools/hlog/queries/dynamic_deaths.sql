-- Every hero death of a game, oldest first (the rule is the fragment hero_death): team of the hero who died, t, n deaths at t.
-- Params: file (absolute log path, as in games.file), game (default 1). No metric reads it since part C
-- (@dynamic_world includes the fragment for its kill bursts); test/dynamic.test.js pins the rule through it.
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
-- include: hero_death
x AS (SELECT 1)
SELECT team, t, n FROM death ORDER BY t
