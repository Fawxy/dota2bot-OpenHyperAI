-- The per-second hero series of a game (the fragment hero_second; docs/team/slices/retire-dynamic-b.md): one row per hero and
-- whole second from its first snapshot with x to the last snapshot of any hero, the latest snapshot at or before it (alive 0 in
-- a death gap). No metric reads it since part C (the queries include the fragment); it is there to look at, and
-- test/dynamic.test.js pins the death-gap rule through it. Params: file (absolute log path, as in games.file), game (default 1).
WITH RECURSIVE gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
x AS (SELECT 1)
SELECT pid, s, x, y, alive, mode FROM hs_sec ORDER BY pid, s
