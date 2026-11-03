-- Cores' pre-hits under our tower (slice pre-hit, states/pre_hit): one row per game and team whose file matches :like (default
-- every game), before :until (s, default 600). From ev=prehit (one per attempt): `n` attempts, `fired` those whose attack fired
-- (result ok), `lost` those whose creep died first (no_target), `missed` the attack never fired. From ev=lh: `lh_after` our
-- landed last hits on a creep the same core pre-hit (ph=1), `tried_after` last-hit attempts on one; `lh_per_prehit` lh_after
-- over fired (the slice's target). Teams with no pre-hit attempt have no row.
-- ensure: ev_prehit(pid, result, reason)
-- ensure: ev_lh(pid, kind, result, ph)
-- ensure: ev_bot(pid, team, pos)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
core AS (SELECT l.game_id, l.team, l.pid FROM lineup l WHERE l.game_id IN (SELECT game_id FROM gm) AND l.pos BETWEEN 1 AND 3),
pre AS (
    SELECT c.game_id, c.team, count(*) AS n, sum(p.result = 'ok') AS fired, sum(p.reason = 'no_target') AS lost,
        sum(p.reason = 'missed') AS missed
    FROM ev_prehit p JOIN core c ON c.game_id = p.game_id AND c.pid = p.pid
    WHERE p.t < coalesce(:until, 600)
    GROUP BY c.game_id, c.team
),
after AS (
    SELECT c.game_id, c.team, count(*) AS tried_after, sum(l.result = 'ok') AS lh_after
    FROM ev_lh l JOIN core c ON c.game_id = l.game_id AND c.pid = l.pid
    WHERE l.t < coalesce(:until, 600) AND l.kind = 'lasthit' AND l.ph = 1
    GROUP BY c.game_id, c.team
)
SELECT gm.file, p.game_id, p.team, p.n, p.fired, p.lost, p.missed,
    coalesce(a.tried_after, 0) AS tried_after, coalesce(a.lh_after, 0) AS lh_after,
    CASE WHEN p.fired > 0 THEN round(1.0 * coalesce(a.lh_after, 0) / p.fired, 2) END AS lh_per_prehit
FROM pre p JOIN gm ON gm.game_id = p.game_id LEFT JOIN after a ON a.game_id = p.game_id AND a.team = p.team
ORDER BY p.game_id, p.team;
