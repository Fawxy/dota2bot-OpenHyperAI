-- Grade the log's unit_life against the replay's, for a game that `hlog.js replay` has read (rp_game): the log's own units (CTE unit_life_log: the
-- death events' rows, or ev=unit_seen / unit_gone's in a game from team-bots bfc08402) are paired to the replay's units that died (rp_unit, the
-- truth) by kind, team (a lane creep's owner), type (a flag bearer is a melee creep, as the log's old events have it) and place: a death within 3 s
-- and 600 units, mutually nearest by distance. That is wider than unit_life's own 1 s and 250, so the death time and spot can disagree; the pairing
-- exists for this grade only and units are matched nowhere else. A log row that is only a sighting (uid `:x`: a creep the other team saw leave its
-- list, maybe into fog) is no death and is counted apart.
-- The 124 banked replays (to 18/11/2026) all predate ev=unit_seen, so for them the log side is the old path: the owner's wave_creep_death or
-- own_creep_death, paired to the other team's creep_death for an enemy hero's last hit, and neutral_death. A game recorded from bfc08402 on is graded
-- on unit_seen / unit_gone, with the enemy taker still paired.
-- Params: like (a run label or log path fragment) with game (its number in the log, default the last), or game_id.
-- Rows, in three sections (section, kind, by_kind):
--   paired       the replay's deaths a log row pairs to, by the replay's by_kind (hero, deny, tower, creep, neutral, unknown): n; agree (the log's
--                by_kind is the replay's, and its pid when a hero or deny); log_unknown (the log names no killer: the creep and neutral kills it
--                cannot see); wrong (the log names another killer or another hero); t_ok (death times within 1 s); spot_ok (within 250 units);
--                mean_dt (s) and mean_d (units) over the pairs
--   replay_only  replay deaths with no log row, by the replay's by_kind (what the log lacks)
--   log_only     log deaths with no replay death; log_sighting: log rows that are only sightings
-- A replay row marked amb (like units died within 0.1 s with different killers) pairs like the rest; its killer may be swapped with its twin's.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id FROM games g
    WHERE g.game_id = :game_id
        OR (:like IS NOT NULL AND g.file LIKE :like AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)))
),
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen WHERE game_id IN (SELECT game_id FROM gm)),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone WHERE game_id IN (SELECT game_id FROM gm)),
ul_rp AS NOT MATERIALIZED (SELECT * FROM rp_unit WHERE game_id IN (SELECT game_id FROM gm)),
-- include: unit_life_rows
gl AS MATERIALIZED (
    SELECT game_id, uid, kind, team, CASE WHEN type = 'siege' THEN 'siege' WHEN type = 'ranged' THEN 'ranged' WHEN kind = 'neutral' THEN 'neutral' ELSE 'melee' END AS ty,
        t1, x1, y1, by_kind, by_pid, uid LIKE '%:x%' AS sighting
    FROM unit_life_log WHERE game_id IN (SELECT game_id FROM rp_game) AND t1 IS NOT NULL
),
gr AS MATERIALIZED (
    SELECT game_id, uid, kind, team, CASE WHEN type = 'siege' THEN 'siege' WHEN type = 'ranged' THEN 'ranged' WHEN kind = 'neutral' THEN 'neutral' ELSE 'melee' END AS ty,
        t1, x1, y1, by_kind, by_pid
    FROM ul_rp WHERE end = 'death' AND game_id IN (SELECT game_id FROM rp_game)
),
gpair AS MATERIALIZED (
    SELECT game_id, luid, ruid FROM (
        SELECT game_id, luid, ruid,
            row_number() OVER (PARTITION BY game_id, luid ORDER BY d2, dt, ruid) AS rl,
            row_number() OVER (PARTITION BY game_id, ruid ORDER BY d2, dt, luid) AS rr
        FROM (
            SELECT l.game_id, l.uid AS luid, r.uid AS ruid, abs(r.t1 - l.t1) AS dt,
                (r.x1 - l.x1) * (r.x1 - l.x1) + (r.y1 - l.y1) * (r.y1 - l.y1) AS d2
            FROM gl l JOIN gr r ON r.game_id = l.game_id AND r.kind = l.kind AND r.team = l.team AND r.ty = l.ty
                AND r.t1 BETWEEN l.t1 - 3 AND l.t1 + 3 AND (r.x1 - l.x1) * (r.x1 - l.x1) + (r.y1 - l.y1) * (r.y1 - l.y1) <= 360000
            WHERE NOT l.sighting
        )
    ) WHERE rl = 1 AND rr = 1
),
gj AS (
    SELECT r.by_kind AS by_kind, r.kind AS kind,
        l.by_kind = r.by_kind AND (r.by_kind NOT IN ('hero', 'deny') OR l.by_pid IS r.by_pid) AS agree,
        l.by_kind = 'unknown' AS log_unknown,
        abs(r.t1 - l.t1) AS dt, sqrt((r.x1 - l.x1) * (r.x1 - l.x1) + (r.y1 - l.y1) * (r.y1 - l.y1)) AS d
    FROM gpair p JOIN gl l ON l.game_id = p.game_id AND l.uid = p.luid JOIN gr r ON r.game_id = p.game_id AND r.uid = p.ruid
)
SELECT 'paired' AS section, kind, by_kind, count(*) AS n, sum(agree) AS agree, sum(log_unknown) AS log_unknown,
    sum(NOT agree AND NOT log_unknown) AS wrong, sum(dt <= 1) AS t_ok, sum(d <= 250) AS spot_ok, round(avg(dt), 2) AS mean_dt, round(avg(d)) AS mean_d
FROM gj GROUP BY kind, by_kind
UNION ALL
SELECT 'replay_only', r.kind, r.by_kind, count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM gr r WHERE NOT EXISTS (SELECT 1 FROM gpair p WHERE p.game_id = r.game_id AND p.ruid = r.uid) GROUP BY r.kind, r.by_kind
UNION ALL
SELECT 'log_only', l.kind, NULL, count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM gl l WHERE NOT l.sighting AND NOT EXISTS (SELECT 1 FROM gpair p WHERE p.game_id = l.game_id AND p.luid = l.uid) GROUP BY l.kind
UNION ALL
SELECT 'log_sighting', l.kind, NULL, count(*), NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM gl l WHERE l.sighting GROUP BY l.kind
ORDER BY 1, 2, 3
