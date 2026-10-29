-- Creep deaths by who got them: `by` is a pid, `deny` (an enemy deny) or `none` (no claimed killer); only creeps that
-- died near a hero are logged (ev=creep_death), so this is not a count of all creeps.
-- needs: ev_creep_death(team, kind, by)
SELECT g.file, g.game, c.team, c.kind, c."by" AS killer, count(*) AS n, min(c.t) AS first_t
FROM ev_creep_death c JOIN games g USING (game_id)
GROUP BY c.game_id, c.team, c.kind, c."by"
