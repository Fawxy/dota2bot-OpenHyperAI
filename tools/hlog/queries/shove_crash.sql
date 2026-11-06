-- The shove's crash (slice lane-controller slice 1, states/idle_swing kind shove) in games whose file matches :like: one row per
-- game, team and lane over the 30 s wave cycles from 1:00 to 10:00 (ev=lane_read, once a second per team and lane): `cycles`
-- with a reading, `crashed` those whose clash reached their T1's range at some reading (eq >= 0.75: our front within about 700
-- of their tower on a side lane, `judgement`), `share` crashed / cycles, `shoves` the team's ev=idle_swing kind=shove lines in
-- the whole game (the swing line carries no lane, so the count is per team, repeated on each of its lanes; the reader names
-- the forced lane).
-- ensure: ev_lane_read(team, lane, eq)
-- ensure: ev_idle_swing(pid, kind)
-- ensure: ev_bot(pid, team)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
cyc AS (
    SELECT game_id, team, lane, CAST(t / 30 AS INTEGER) AS c, max(eq) AS eqmax
    FROM ev_lane_read
    WHERE game_id IN (SELECT game_id FROM gm) AND t >= 60 AND t < 600 AND eq IS NOT NULL
    GROUP BY 1, 2, 3, 4
),
tm AS (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
sh AS (
    SELECT i.game_id, tm.team, count(*) AS n
    FROM ev_idle_swing i JOIN tm ON tm.game_id = i.game_id AND tm.pid = i.pid
    WHERE i.kind = 'shove' AND i.game_id IN (SELECT game_id FROM gm)
    GROUP BY 1, 2
)
SELECT cyc.game_id, cyc.team, cyc.lane, count(*) AS cycles, sum(eqmax >= 0.75) AS crashed,
    round(1.0 * sum(eqmax >= 0.75) / count(*), 2) AS share, coalesce(max(sh.n), 0) AS shoves
FROM cyc LEFT JOIN sh ON sh.game_id = cyc.game_id AND sh.team = cyc.team
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
