-- Fragment (`-- include: ep_second`): the seconds every shared episode is cut from. The including query defines `gm(game_id, ...)`
-- and `ep_win(lo, hi)`, the game seconds to read (one row), first. CTEs:
--   ep_who(game_id, pid, team, pos, hero)   each hero, from its last ev=bot or ev=player line; pos from view lineup
--   ep_gap(game_id, pid, dsec, gsec)        each death (ep_death) in whole seconds: not playing in (dsec, gsec]
--   ep_sec(game_id, pid, team, pos, sec, seq, x, y, hp, alive, mode, tid, life, live)   a hero's last snapshot in each whole
--       second (rounded). life: its deaths so far. live: alive, HP above 0 and not between a death and the snapshot before
--       its respawn.
-- Ends with a comma.
-- ensure: ev_bot(pid, team, pos, hero)
-- ensure: ev_player(pid, team, hero)
-- ensure: ev_snap(pid, x, y, hp, alive, mode, tid, deaths)
-- include: ep_death
ep_who AS MATERIALIZED (
    SELECT w.game_id, w.pid, w.team, l.pos, w.hero FROM (
        SELECT game_id, pid, team, hero, row_number() OVER (PARTITION BY game_id, pid ORDER BY seq DESC) AS rn
        FROM (
            SELECT game_id, pid, team, hero, seq FROM ev_bot
            WHERE game_id IN (SELECT game_id FROM gm) AND pid IS NOT NULL AND team IS NOT NULL
            UNION ALL
            SELECT game_id, pid, team, hero, seq FROM ev_player
            WHERE game_id IN (SELECT game_id FROM gm) AND pid IS NOT NULL AND team IS NOT NULL
        )
    ) w LEFT JOIN lineup l ON l.game_id = w.game_id AND l.pid = w.pid
    WHERE w.rn = 1
),
eps_raw AS MATERIALIZED (
    SELECT * FROM (
        SELECT s.game_id, s.pid, CAST(round(s.t) AS INTEGER) AS sec, s.seq, s.x, s.y, s.hp, s.alive, s.mode,
            CAST(s.tid AS TEXT) AS tid,
            row_number() OVER (PARTITION BY s.game_id, s.pid, CAST(round(s.t) AS INTEGER) ORDER BY s.seq DESC) AS rn
        FROM gm CROSS JOIN ep_win CROSS JOIN ev_snap s ON s.game_id = gm.game_id AND s.t >= ep_win.lo AND s.t <= ep_win.hi
        WHERE s.x IS NOT NULL
    ) WHERE rn = 1
),
ep_gap AS MATERIALIZED (
    SELECT game_id, pid, CAST(round(t) AS INTEGER) AS dsec, CAST(round(gap) AS INTEGER) AS gsec FROM ep_death
),
ep_sec AS MATERIALIZED (
    SELECT r.game_id, r.pid, w.team, w.pos, r.sec, r.seq, r.x, r.y, r.hp, r.alive, r.mode, r.tid,
        (SELECT count(*) FROM ep_gap d WHERE d.game_id = r.game_id AND d.pid = r.pid AND d.gsec < r.sec) AS life,
        r.alive IS NOT 0 AND coalesce(r.hp, 1) > 0 AND NOT EXISTS (
            SELECT 1 FROM ep_gap d WHERE d.game_id = r.game_id AND d.pid = r.pid AND r.sec > d.dsec AND r.sec <= d.gsec) AS live
    FROM eps_raw r JOIN ep_who w ON w.game_id = r.game_id AND w.pid = r.pid
),
