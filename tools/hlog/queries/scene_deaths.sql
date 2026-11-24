-- Lane creep and neutral deaths with their place in a window, for `hlog.js scene`: one row per death (the timeline's rule: view
-- creep_fate, fragment creep_fate_rows), oldest first. Not read: an enemy deny (the denier's own_deny row is the death), and an
-- own-side `lost` the other team's log has as its own enemy-side death.
-- Params: game_id (games.game_id), lo and hi (seconds).
-- Row: t, team (the logging team for a lane creep: its creep when side = own, the creep of the other team when side = enemy), side
-- (enemy, own, neutral), kind (melee, ranged, siege, neutral), x, y, fate (own_lh, own_deny, other, lost, neutral), pid (the hero credited:
-- a text `none` for a neutral nobody credited), camp (neutral only).
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
WITH cf_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id = :game_id AND t >= :lo - 1.0 AND t <= :hi + 1.0),
cf_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id = :game_id AND t >= :lo - 1.0 AND t <= :hi + 1.0),
-- include: creep_fate_rows
SELECT t, team, side, kind, x, y, fate, pid, NULL AS camp FROM (
    SELECT f.* FROM creep_fate_rows f
    WHERE f.t >= :lo AND f.t <= :hi AND f.fate <> 'enemy_deny'
        AND NOT (f.side = 'own' AND f.fate = 'lost' AND EXISTS (
            SELECT 1 FROM creep_fate_rows e WHERE e.side = 'enemy' AND e.fate IN ('own_lh', 'other')
                AND e.team <> f.team AND e.kind IS f.kind AND e.t BETWEEN f.t - 1.0 AND f.t + 1.0
                AND (e.x - f.x) * (e.x - f.x) + (e.y - f.y) * (e.y - f.y) <= 62500))
)
UNION ALL
SELECT t, team, 'neutral', kind, x, y, 'neutral', "by", camp FROM ev_neutral_death
WHERE game_id = :game_id AND t >= :lo AND t <= :hi
ORDER BY t
