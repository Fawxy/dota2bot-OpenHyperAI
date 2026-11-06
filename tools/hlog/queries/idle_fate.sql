-- The idle swing's creeps keyed by creep id (slice lane-control 2b; review 2026-11-06-idle-swing-014bae7 F2, F3), in games
-- whose file matches :like. Logs from build 2b on carry `cid` on ev=idle_swing, ev=creep_death and ev=own_creep_death; older
-- logs give no rows here (use @idle_swings, the place match). One row per kind (predeny, setup, shove): `creeps` the distinct
-- creeps a team swung at with an ok swing (two laners on one creep count once), `swings` the ok swings on them.
-- predeny, from the team's own_creep_death with that cid: `ours` denied by one of our heroes, `lost_hero` died with no deny of
-- ours and the other team's creep_death names an enemy hero's last hit at its place (1 s, 150), `lost_other` the rest (a creep
-- or tower kill), `unmatched` no death logged (alive, or a death the 50% rule or the hero-near rule did not log).
-- setup and shove, from the team's creep_death with that cid: `ours` one of our heroes' last hit, `lost_hero` their deny
-- (by=deny), `lost_other` no hero (by=none), `unmatched` no death logged. `rate` = ours / creeps, the per-attempt measure
-- (predeny: pre-denied creeps that end as our deny; setup: setups that end as our last hit).
-- ensure: ev_idle_swing(pid, kind, result, cid)
-- ensure: ev_bot(pid, team)
-- ensure: ev_own_creep_death(team, x, y, by, cid)
-- ensure: ev_creep_death(team, x, y, by, cid)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
s AS MATERIALIZED (
    SELECT i.game_id, tm.team, i.kind, i.cid, count(*) AS swings
    FROM ev_idle_swing i JOIN tm ON tm.game_id = i.game_id AND tm.pid = i.pid
    WHERE i.game_id IN (SELECT game_id FROM gm) AND i.result = 'ok' AND i.cid IS NOT NULL
    GROUP BY 1, 2, 3, 4
),
od AS MATERIALIZED (
    SELECT game_id, team, cid, min(t) AS t, min(x) AS x, min(y) AS y, min(CAST(by AS TEXT)) AS by
    FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM gm) AND cid IS NOT NULL GROUP BY 1, 2, 3
),
cd AS MATERIALIZED (
    SELECT game_id, team, cid, min(CAST(by AS TEXT)) AS by
    FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM gm) AND cid IS NOT NULL GROUP BY 1, 2, 3
),
f AS (
    SELECT s.kind, s.swings,
        CASE
            WHEN s.kind = 'predeny' THEN (
                CASE
                    WHEN od.cid IS NULL THEN 'unmatched'
                    WHEN od.by IN (SELECT CAST(pid AS TEXT) FROM tm WHERE tm.game_id = s.game_id AND tm.team = s.team) THEN 'ours'
                    WHEN EXISTS (
                        SELECT 1 FROM ev_creep_death e
                        WHERE e.game_id = s.game_id AND e.team <> s.team AND abs(e.t - od.t) <= 1
                            AND (e.x - od.x) * (e.x - od.x) + (e.y - od.y) * (e.y - od.y) <= 150 * 150
                            AND CAST(e.by AS TEXT) GLOB '[0-9]*'
                    ) THEN 'lost_hero'
                    ELSE 'lost_other'
                END)
            ELSE (
                CASE
                    WHEN cd.cid IS NULL THEN 'unmatched'
                    WHEN cd.by IN (SELECT CAST(pid AS TEXT) FROM tm WHERE tm.game_id = s.game_id AND tm.team = s.team) THEN 'ours'
                    WHEN cd.by = 'deny' THEN 'lost_hero'
                    ELSE 'lost_other'
                END)
        END AS fate
    FROM s
    LEFT JOIN od ON od.game_id = s.game_id AND od.team = s.team AND od.cid = s.cid
    LEFT JOIN cd ON cd.game_id = s.game_id AND cd.team = s.team AND cd.cid = s.cid
)
SELECT kind, count(*) AS creeps, sum(swings) AS swings,
    sum(fate = 'ours') AS ours, sum(fate = 'lost_hero') AS lost_hero, sum(fate = 'lost_other') AS lost_other,
    sum(fate = 'unmatched') AS unmatched, round(1.0 * sum(fate = 'ours') / max(count(*), 1), 2) AS rate
FROM f GROUP BY kind ORDER BY kind;
