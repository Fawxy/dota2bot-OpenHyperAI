-- Where the shadow arbiter's pick (ev=arb, slice arbiter-shadow) names a host mode other than the one Valve holds the hero in:
-- seconds by role, pick, active mode and the source of the desire that held the hero, with that desire's range. The pick in
-- force at each snap is the latest ev=arb line at or before it for that hero; `oha` (nothing of ours applies) always agrees,
-- and agreement is the pick's host against the snap's own mode. A snap whose mode that ev=arb line had not yet seen is left
-- out: the shadow reads every 0.25 s, so a mode Valve held for a frame would be paired with the pick before it. The source
-- is the snap's `by` ("<mode> <desire> by <source>"; see @mode_hold to find the branch); it and the desire are NULL where
-- `by` does not name the active mode, as for Valve's built-in modes (evasive, item, defend_ally), which have no mode file.
-- The drive's own and end lines (`ph`, rework step 7) name no pick and are skipped.
-- Params: like (LIKE pattern on games.file), from, until (seconds, default 90 and 600), pos_lo, pos_hi (lineup positions,
-- default 1-5), min_secs (default 1).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
s AS (
    SELECT a.game_id, a.mode, a.by, a.pos, a.by LIKE a.mode || ' % by %' AS named,
        (SELECT r.seq FROM ev_arb r WHERE r.game_id = a.game_id AND r.pid = a.pid AND r.t <= a.t AND r.ph IS NULL ORDER BY r.t DESC, r.seq DESC LIMIT 1) AS arb_seq
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
      AND a.pos BETWEEN coalesce(:pos_lo, 1) AND coalesce(:pos_hi, 5)
),
h AS (
    SELECT s.game_id, CASE WHEN s.pos <= 3 THEN 'core' ELSE 'sup' END AS role, r.pick, r.host, r.act AS seen, s.mode,
        CASE WHEN s.named THEN CAST(substr(s.by, instr(s.by, ' ') + 1, instr(s.by, ' by ') - instr(s.by, ' ') - 1) AS REAL) END AS desire,
        CASE WHEN s.named THEN substr(s.by, instr(s.by, ' by ') + 4) END AS src
    FROM s JOIN ev_arb r ON r.game_id = s.game_id AND r.seq = s.arb_seq
)
SELECT role, pick, mode AS act, src, count(*) AS secs, round(min(desire), 2) AS lo, round(max(desire), 2) AS hi, count(DISTINCT game_id) AS games
FROM h
WHERE pick <> 'oha' AND host IS NOT mode AND seen IS mode
GROUP BY role, pick, mode, src
HAVING count(*) >= coalesce(:min_secs, 1)
ORDER BY role, secs DESC
