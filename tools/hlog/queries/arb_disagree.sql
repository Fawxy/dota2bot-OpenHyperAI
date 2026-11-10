-- Where the shadow arbiter's pick (ev=arb, slice arbiter-shadow) names a host mode other than the one Valve holds the hero in:
-- seconds by pick and active mode, with the desire value and source of the mode that held the hero. The pick in force at each
-- snap is the latest ev=arb line at or before it for that hero; `oha` (nothing of ours applies) always agrees, and agreement
-- is the pick's host against the snap's own mode. The desire is the snap's `by` ("<mode> <desire> by <source>"), rounded to
-- 0.01 (see @mode_hold: grep the mode file for the value to find the branch); both are NULL where `by` does not name the
-- active mode, as for Valve's built-in modes (evasive, item, defend_ally), which have no mode file.
-- Params: like (LIKE pattern on games.file), from, until (seconds, default 90 and 600), pos_lo, pos_hi (lineup positions,
-- default 1-3, the cores).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
s AS (
    SELECT a.game_id, a.mode, a.by, a.by LIKE a.mode || ' % by %' AS named,
        (SELECT r.seq FROM ev_arb r WHERE r.game_id = a.game_id AND r.pid = a.pid AND r.t <= a.t ORDER BY r.t DESC, r.seq DESC LIMIT 1) AS arb_seq
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
      AND a.pos BETWEEN coalesce(:pos_lo, 1) AND coalesce(:pos_hi, 3)
),
h AS (
    SELECT s.game_id, r.pick, r.host, s.mode,
        CASE WHEN s.named THEN CAST(substr(s.by, instr(s.by, ' ') + 1, instr(s.by, ' by ') - instr(s.by, ' ') - 1) AS REAL) END AS desire,
        CASE WHEN s.named THEN substr(s.by, instr(s.by, ' by ') + 4) END AS src
    FROM s JOIN ev_arb r ON r.game_id = s.game_id AND r.seq = s.arb_seq
)
SELECT pick, mode AS act, round(desire, 2) AS desire, src, count(*) AS secs, count(DISTINCT game_id) AS games
FROM h
WHERE pick <> 'oha' AND host IS NOT mode
GROUP BY pick, mode, round(desire, 2), src
ORDER BY secs DESC
