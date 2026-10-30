-- Stack attempts of one game (slice 4, KR S.2a; replaces dynamic.js `stackAttempts` over the parsed game): one row per ev=stack
-- line before `until`, in log order, with the stack_attempts view's columns (its `cause`, `left59` and `death_flag` rules).
-- Params: file (absolute log path, as in games.file), game (default 1), until (s, default none).
-- A '?' or absent field is NULL and true/false are 1/0 (the store's rule), where the parsed game kept '?' and 'true'.
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1))
SELECT * FROM stack_attempts
WHERE game_id = (SELECT game_id FROM gm) AND t < coalesce(:until, 1e9)
ORDER BY seq
