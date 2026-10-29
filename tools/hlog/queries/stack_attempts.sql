-- Stack attempts per game by result and cause (proposal step 2: must equal stacks.js --json on the slice 4 logs).
-- Like stacks.js: the first game of each log only. Params: until (s, default none).
SELECT file, res, cause, count(*) AS n
FROM stack_attempts
WHERE game = 1 AND t < coalesce(:until, 1e9)
GROUP BY file, res, cause
ORDER BY file, res, cause
