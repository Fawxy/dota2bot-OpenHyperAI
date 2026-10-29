-- One row per game (dynamic.js part A, docs/team/slices/retire-dynamic-a.md): the game-level counts dynamicMetrics reads.
-- Params: file (absolute log path, as in games.file), game (default 1).
--   end                 the last whole minute of snapshots; bots = heroes with a team and a snapshot (`hs_bot`)
--   enc10, enc_after    encounters with onset in [0, 10:00) and [10:00, end): an opposing pair, both alive, within 1200 units
--                       after at least 5 s apart (the scan starts at 0:00); an onset within 3 s of the current encounter's first
--                       onset joins it (`C.R_AWARE`, `C.GAP_ENC`, `C.MERGE_ENC`)
--   deaths, deaths10_r, deaths10_d   deaths (each deaths-counter increment, dated at the last snapshot before a gap over 2.5 s,
--                       plus one for a hero dead at the end), and those before 10:00 per team
--   fights10, fights_after   runs of 3+ deaths no more than 15 s apart in [0, 10:00) and [10:00, end) (`C.FIGHT_GAP`,
--                       `C.FIGHT_MIN_DEATHS`)
--   lua_error_ours, console_lines, console_errors, squelches, error_squelches   ev=lua_error lines; console error lines, those
--                       saying "script runtime error"; squelch notices, those right after an error line
-- ensure: ev_lua_error(pid)
WITH RECURSIVE gm AS (SELECT game_id FROM games WHERE file = :file AND game = coalesce(:game, 1)),
-- include: hero_second
gend AS (SELECT CAST(floor((SELECT last FROM hs_last) / 60) AS INTEGER) * 60 AS e),
close AS (
    SELECT a.pid AS ap, b.pid AS bp, a.s
    FROM hs_sec a JOIN hs_sec b ON b.s = a.s AND b.team = 3
    WHERE a.team = 2 AND a.s >= 0 AND a.alive IS NOT 0 AND b.alive IS NOT 0
      AND sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)) <= 1200
),
onset AS (
    SELECT DISTINCT CASE WHEN s < 600 THEN 1 ELSE 2 END AS w, s
    FROM (SELECT s, lag(s) OVER (PARTITION BY ap, bp ORDER BY s) AS ps FROM close)
    WHERE (ps IS NULL OR s - ps >= 6)
      AND (s < 600 OR s < (SELECT e FROM gend))
),
ord AS (SELECT w, s, row_number() OVER (PARTITION BY w ORDER BY s) AS rn FROM onset),
enc(w, rn, first, n) AS (
    SELECT w, rn, s, 1 FROM ord WHERE rn = 1
    UNION ALL
    SELECT o.w, o.rn, CASE WHEN o.s - e.first > 3 THEN o.s ELSE e.first END, e.n + (o.s - e.first > 3)
    FROM enc e JOIN ord o ON o.w = e.w AND o.rn = e.rn + 1
),
-- include: hero_death
run AS (
    SELECT w, sum(brk) OVER (PARTITION BY w ORDER BY t ROWS UNBOUNDED PRECEDING) AS id, n
    FROM (SELECT w, t, n, CASE WHEN t - lag(t) OVER (PARTITION BY w ORDER BY t) <= 15 THEN 0 ELSE 1 END AS brk
          FROM (SELECT CASE WHEN t < 600 THEN 1 ELSE 2 END AS w, t, n FROM death
                WHERE t >= 0 AND (t < 600 OR t < (SELECT e FROM gend))))
),
fight AS (SELECT w, count(*) AS k FROM (SELECT w, id FROM run GROUP BY w, id HAVING sum(n) >= 3) GROUP BY w)
SELECT (SELECT e FROM gend) AS "end",
    (SELECT count(*) FROM hs_bot) AS bots,
    coalesce((SELECT max(n) FROM enc WHERE w = 1), 0) AS enc10,
    coalesce((SELECT max(n) FROM enc WHERE w = 2), 0) AS enc_after,
    (SELECT coalesce(sum(n), 0) FROM death) AS deaths,
    (SELECT coalesce(sum(n), 0) FROM death WHERE team = 2 AND t < 600) AS deaths10_r,
    (SELECT coalesce(sum(n), 0) FROM death WHERE team = 3 AND t < 600) AS deaths10_d,
    coalesce((SELECT k FROM fight WHERE w = 1), 0) AS fights10,
    coalesce((SELECT k FROM fight WHERE w = 2), 0) AS fights_after,
    (SELECT count(*) FROM ev_lua_error WHERE game_id = (SELECT game_id FROM gm)) AS lua_error_ours,
    (SELECT count(*) FROM errors WHERE game_id = (SELECT game_id FROM gm)) AS console_lines,
    (SELECT count(*) FROM errors WHERE game_id = (SELECT game_id FROM gm) AND text LIKE '%script runtime error%') AS console_errors,
    (SELECT coalesce(squelches, 0) FROM games WHERE game_id = (SELECT game_id FROM gm)) AS squelches,
    (SELECT coalesce(error_squelches, 0) FROM games WHERE game_id = (SELECT game_id FROM gm)) AS error_squelches
