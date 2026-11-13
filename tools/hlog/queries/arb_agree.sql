-- The drive's fact check (rework step 7, Ours.ArbiterDrive): for each owned hero, the share of lane-activity seconds under a
-- pick of ours (ev=arb, not `oha`) in which Valve held the hero in the pick's host mode. The drill passes at 0.9 for every
-- hero; @arb_disagree names the seconds that miss. The pick in force at each snap is the latest ev=arb pick line at or
-- before it (the `ph` own and end lines name no pick and are skipped).
-- Params: like (LIKE pattern on games.file), from, until (seconds, default 90 and 600).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
s AS (
    SELECT a.game_id, a.pid, a.pos, a.mode,
        (SELECT r.seq FROM ev_arb r WHERE r.game_id = a.game_id AND r.pid = a.pid AND r.t <= a.t AND r.ph IS NULL ORDER BY r.t DESC, r.seq DESC LIMIT 1) AS arb_seq
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.t >= coalesce(:from, 90) AND a.t <= coalesce(:until, 600)
)
SELECT s.game_id AS game, s.pid, s.pos, count(*) AS secs, sum(r.host IS s.mode) AS agree,
    round(1.0 * sum(r.host IS s.mode) / count(*), 3) AS share
FROM s JOIN ev_arb r ON r.game_id = s.game_id AND r.seq = s.arb_seq
WHERE r.pick <> 'oha'
GROUP BY s.game_id, s.pid, s.pos
ORDER BY share, s.game_id, s.pid
