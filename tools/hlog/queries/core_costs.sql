-- Costs of a core's lane play at `until` (slice 5, KR L.1): one row per core (lineup position 1-3 of each team, as
-- @lasthit_cores) with its denies, level and deaths from the last ev=snap at or before `until`, and `hph`, the HP it has lost
-- to heroes since the game began (states/lane_metrics HeroLost, cumulative), from its last ev=lane_pos at or before `until`.
-- ev=lane_pos is logged only while the bot is in the laning state, so `hph` is a lower bound for a core that left its lane;
-- NULL when the build logs no lane_pos. Params: file (absolute log path, as in games.file), game (default 1), until (s, default 600).
-- ensure: ev_snap(pid, x, dn, lvl, deaths)
-- ensure: ev_lane_pos(pid, hph)
-- ensure: ev_bot(pid, team, pos)
WITH gm AS (SELECT +game_id AS game_id FROM games WHERE file = :file AND game = coalesce(:game, 1))
SELECT l.team, l.pos, l.pid,
    (SELECT s.dn FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL AND s.dn IS NOT NULL
        AND s.t <= coalesce(:until, 600) ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS dn,
    (SELECT s.lvl FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL AND s.lvl IS NOT NULL
        AND s.t <= coalesce(:until, 600) ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS lvl,
    (SELECT s.deaths FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL AND s.deaths IS NOT NULL
        AND s.t <= coalesce(:until, 600) ORDER BY s.t DESC, s.seq DESC LIMIT 1) AS deaths,
    (SELECT p.hph FROM ev_lane_pos p WHERE p.game_id = l.game_id AND p.pid = l.pid AND p.hph IS NOT NULL
        AND p.t <= coalesce(:until, 600) ORDER BY p.t DESC, p.seq DESC LIMIT 1) AS hph
FROM lineup l
WHERE l.game_id = (SELECT game_id FROM gm) AND l.pos BETWEEN 1 AND 3
  AND EXISTS (SELECT 1 FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.x IS NOT NULL)
ORDER BY l.team, l.pos
