-- Where the shadow arbiter's pick (ev=arb, slice arbiter-shadow) names a host mode other than the one Valve holds the hero in:
-- seconds by pick and active mode, with the desire value and source of the mode that held the hero. The pick in force at each
-- snap is the latest ev=arb line at or before it for that hero; `oha` (nothing of ours applies) always agrees. The desire is the
-- snap's `by` ("<mode> <desire> by <source>"), rounded to 0.01 (see @mode_hold: grep the mode file for the value to find the branch).
-- Params: like (LIKE pattern on games.file), from, until (seconds, default 90 and 600), pos_lo, pos_hi (lineup positions,
-- default 1-3, the cores).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
h AS (
    SELECT a.game_id, a.pid,
        (SELECT r.pick FROM ev_arb r WHERE r.game_id = a.game_id AND r.pid = a.pid AND r.t <= a.t ORDER BY r.t DESC, r.seq DESC LIMIT 1) AS pick,
        (SELECT r.agree FROM ev_arb r WHERE r.game_id = a.game_id AND r.pid = a.pid AND r.t <= a.t ORDER BY r.t DESC, r.seq DESC LIMIT 1) AS agree,
        a.mode,
        CAST(substr(a.by, instr(a.by, ' ') + 1, instr(a.by, ' by ') - instr(a.by, ' ') - 1) AS REAL) AS desire,
        substr(a.by, instr(a.by, ' by ') + 4) AS src
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
      AND a.pos BETWEEN coalesce(:pos_lo, 1) AND coalesce(:pos_hi, 3)
      AND a.by LIKE a.mode || ' % by %'
)
SELECT pick, mode AS act, round(desire, 2) AS desire, src, count(*) AS secs, count(DISTINCT game_id) AS games
FROM h
WHERE agree = 0
GROUP BY pick, mode, round(desire, 2), src
ORDER BY secs DESC
