-- Fragment (`-- include: unit_life_rows`): the one definition of view unit_life's rows (its header has the columns and rules).
-- The including query defines first, each `AS NOT MATERIALIZED`, the death events to read, all columns, of the games it wants
-- (view unit_life: every game; query unit_life and the readers of one run: their own games, so the cost follows the games read;
-- fragment unit_life_in does it for `ul_gm(game_id)`): `ul_wave` the rows of ev_wave_creep_death, `ul_own` of ev_own_creep_death, `ul_enemy` of ev_creep_death, `ul_neu` of
-- ev_neutral_death, and `ul_useen`, `ul_ugone` the rows of ev_unit_seen and ev_unit_gone (from team-bots after 836e2a2d). A game with an ev_unit_seen row is read from those two (below); any other game
-- from the four death events, as before. CTEs `unit_life_log` (the log's rows) and `unit_life_rows(game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind,
-- by_pid, by_src, src, hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near)`. Ends with a comma.
-- A creep_death line (the other team's sighting) is written when a creep at low health leaves the writer's unit list
-- (trackCreepDeaths, telemetry.ts), which can be a creep that went into fog and lived: ev=creep_revive is written if it reappears,
-- with no cid. So a row with by_src = taker whose uid has `:x` (no owner line) is a sighting, not a confirmed death; a paired
-- row is confirmed by the owner's own line.
-- The lane creeps are fragment unit_life_lane (with unit_life_seen) and the neutrals fragment unit_life_neutral; a reader that wants one half includes that.
-- Also `ul_rp`: the rows of rp_unit (written by `hlog.js replay`, always there) of the games wanted, all columns, with t1 NULL unless end = death.
-- include: unit_life_lane
-- include: unit_life_neutral
-- A creep only the taker saw has no lane from an owner's line: its place is labelled (fragment lane_label, under other names).
ul_pts AS (SELECT game_id AS kind, uid AS k, 0 AS seq, t1 AS t, x1 AS x, y1 AS y FROM ul_lall WHERE lane IS NULL),
-- include: lane_label pts=ul_pts lab=ul_lab
ul_all AS (
    SELECT l.game_id, l.uid, l.kind, l.team, l.type, coalesce(l.lane, b.lane) AS lane, l.wave, l.camp, l.t0, l.x0, l.y0, l.t1, l.x1, l.y1, l.by_kind, l.by_pid, l.by_src, l.hid,
        l.cd_seq, l.cd_t, l.cd_x, l.cd_y, l.tw, l.seq, l.hp1, l.near
    FROM ul_lall l LEFT JOIN ul_lab b ON b.kind = l.game_id AND b.k = l.uid AND l.lane IS NULL
),
unit_life_log AS (
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, CAST(by_pid AS INTEGER) AS by_pid, by_src, 'log' AS src, hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near FROM ul_all
    UNION ALL
    SELECT game_id, uid, 'neutral', 4, type, NULL, NULL, camp, t0, x0, y0, t1, x1, y1, by_kind, by_pid, by_src, 'log', hid, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM ul_nlife
),
-- A game with replay rows (rp_game, written by `hlog.js replay`): its units are the replay's, whole (no log row of it is read, and none is paired
-- to one: a unit's uid is the replay's entity and use, `<ent>.<n>`). lane is where the creep was 20 s after it spawned, wave floor(t0 / 30), t1 x1 y1
-- the death (NULL for a unit alive at 12:00 or despawned: those have by_kind NULL), by_kind also creep or neutral, by_src replay (replay_amb: two
-- like units died within 0.1 s with different killers, so the killers may be swapped), src replay. Any other game reads exactly as `unit_life_log`.
-- Fragment wave_fate reads `unit_life_log`, so the pull readers give the same answers with or without a replay; query unit_grade reads both.
unit_life_rows AS (
    SELECT * FROM unit_life_log WHERE game_id NOT IN (SELECT game_id FROM rp_game)
    UNION ALL
    SELECT game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, by_pid,
        CASE WHEN by_kind IS NULL THEN NULL WHEN amb = 1 THEN 'replay_amb' ELSE 'replay' END, 'replay', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM ul_rp
),
