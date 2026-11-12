-- Stack attempts per game by result and cause.
-- The first game of each log only. Params: until (s, default none).
SELECT file, res, cause, count(*) AS n
FROM stack_attempts
WHERE game = 1 AND t < coalesce(:until, 1e9)
GROUP BY file, res, cause
ORDER BY file, res, cause
