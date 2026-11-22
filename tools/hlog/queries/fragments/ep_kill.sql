-- Fragment (`-- include: ep_kill`): the one definition of a kill attempt. Needs what ep_second needs.
-- CTE `ep_kill(game_id, team, tpid, t0, t1, hpmin, killed)`: one side's attack run on a target (ep_run) in which the target was
-- at 40% HP or less (the bar of query kill_chances), or after which it was dead within 5 s (burst from above the bar).
-- killed: that death. A chance nobody attacked is no attempt: that is query kill_chances. Ends with a comma.
-- include: ep_attack
epk_r AS (
    SELECT r.*,
        (SELECT min(s.hp) FROM ep_sec s
            WHERE s.game_id = r.game_id AND s.pid = r.tpid AND s.sec BETWEEN r.t0 AND r.t1 AND s.alive = 1) AS hpmin,
        EXISTS (SELECT 1 FROM ep_gap d WHERE d.game_id = r.game_id AND d.pid = r.tpid AND d.dsec BETWEEN r.t0 AND r.t1 + 5) AS killed
    FROM ep_run r
),
ep_kill AS MATERIALIZED (SELECT * FROM epk_r WHERE killed OR hpmin <= 40),
