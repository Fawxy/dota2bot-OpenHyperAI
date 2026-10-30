-- Creep-economy share per game and team over the first 10:00 (KR L.1, GOALS.md). One row per game_id and logging team.
-- taken = enemy creeps we last hit (own_lh) + our own creeps we denied (own_deny); enemy_deny = enemy creeps an enemy hero denied
-- (left out of the denominator); den = enemy-side rows - enemy_deny + own-side rows (enemy last hits on our creeps, tower and
-- creep kills stay in as misses); share = taken / den. Window t < 600. Needs logs from 406ee95 on: older logs have no own-side
-- rows, so their enemy denies read `other` and the share would be wrong: it reads NULL when a team has no own-side row. The share is per team; per lane and per role
-- are separate questions on creep_fate.
-- ensure: ev_creep_death(team, kind, x, y, by)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
SELECT game_id, team,
    sum(side = 'enemy' AND fate = 'own_lh') AS own_lh,
    sum(side = 'own' AND fate = 'own_deny') AS own_deny,
    sum(side = 'enemy' AND fate = 'enemy_deny') AS enemy_deny,
    sum(side = 'enemy' AND fate = 'other') AS other,
    sum(side = 'own' AND fate = 'lost') AS lost,
    sum(side = 'enemy' AND fate = 'own_lh') + sum(side = 'own' AND fate = 'own_deny') AS taken,
    sum(side = 'enemy' AND fate <> 'enemy_deny') + sum(side = 'own') AS den,
    CASE WHEN sum(side = 'own') = 0 THEN NULL ELSE CAST(sum(side = 'enemy' AND fate = 'own_lh') + sum(side = 'own' AND fate = 'own_deny') AS REAL)
        / (sum(side = 'enemy' AND fate <> 'enemy_deny') + sum(side = 'own')) END AS share
FROM creep_fate
WHERE t < 600
GROUP BY game_id, team
