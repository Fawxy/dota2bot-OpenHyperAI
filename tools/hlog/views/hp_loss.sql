-- What hurt a hero (tool slice hp-loss): one row per hero and second in which its HP fell, and one per death, with the
-- sources of the damage. Filter by game_id (and pid, t): the view reads every snapshot of the games it is asked for.
--   t, x, y     the later snapshot of the pair; for a death (`died` 1) the last live snapshot, since snapshots stop while dead
--   loss        HP-% points lost (a death: all that was left);  loss_hp  the same in HP (`hv`, absent on older builds)
--   basis       `api`: the build logs the damage flags and the attackers (`hc` present), so `src` states facts.
--               `inferred`: an older build; only the hero flag is a fact (and only to 12:00), the rest is what stood near.
--   src         the sources joined by `+`, or `unexplained` (with `api`: damage over time, a spell or a summoned unit
--               once the flags have lapsed). With `api`:
--                 hero     damaged by a hero in the second before the snapshot (`hit`)
--                 tower    damaged by a tower (`ht`)
--                 creep    damaged by a creep (`hc`) with an enemy lane creep attacking the hero (`ac`)
--                 neutral  a neutral attacking the hero (`an`), with the creep flag or with no other source flagged
--                 unit     the creep flag with no lane creep or neutral seen attacking (kind unknown)
--               With `inferred`, every source but `hero` carries `?`: `tower?` within 750 of an enemy tower, `creep?` within
--               520 of the enemy team's lane front on any lane, `neutral?` within 600 of a camp's spawn (@core_spot's and
--               lane_waste's distances). These say what could have reached the hero, not what hit it.
--   hit hc ht   the flags as logged;  ah ac an at  enemy heroes, enemy lane creeps, neutrals and enemy towers whose attack
--               target was the hero, the larger of the pair's two snapshots
--   near_tower near_front near_camp   the `inferred` tests, on every row
-- A death's flags and attackers are the last live snapshot's, so a killing blow from a source that arrived after it is missed.
-- needs: ev_snap(hv, hit, hc, ht, ah, ac, an, at, deaths)
-- ensure: ev_front(team, topx, topy, midx, midy, botx, boty)
WITH
-- include: camp_spawns
-- include: towers
pr AS (
    SELECT s.game_id, s.pid, s.t, s.x, s.y, s.hp, s.hv, s.hit, s.hc, s.ht, s.ah, s.ac, s.an, s."at", s.deaths,
        lag(s.t) OVER w AS t0, lag(s.x) OVER w AS x0, lag(s.y) OVER w AS y0, lag(s.hp) OVER w AS hp0, lag(s.hv) OVER w AS hv0,
        lag(s.hit) OVER w AS hit0, lag(s.hc) OVER w AS hc0, lag(s.ht) OVER w AS ht0, lag(s.ah) OVER w AS ah0,
        lag(s.ac) OVER w AS ac0, lag(s.an) OVER w AS an0, lag(s."at") OVER w AS at0, lag(s.deaths) OVER w AS deaths0
    FROM ev_snap s WHERE s.alive = 1
    WINDOW w AS (PARTITION BY s.game_id, s.pid ORDER BY s.t)
),
-- One pass over `pr` (a UNION would materialise it for every game): a pair is a death or a loss, never both.
r AS (
    SELECT game_id, pid, deaths > deaths0 AS died,
        CASE WHEN deaths > deaths0 THEN t0 ELSE t END AS t, CASE WHEN deaths > deaths0 THEN x0 ELSE x END AS x,
        CASE WHEN deaths > deaths0 THEN y0 ELSE y END AS y,
        CASE WHEN deaths > deaths0 THEN hp0 ELSE hp0 - hp END AS loss, CASE WHEN deaths > deaths0 THEN hv0 ELSE hv0 - hv END AS loss_hp,
        CASE WHEN deaths > deaths0 THEN hit0 ELSE hit END AS hit, CASE WHEN deaths > deaths0 THEN hc0 ELSE hc END AS hc,
        CASE WHEN deaths > deaths0 THEN ht0 ELSE ht END AS ht,
        CASE WHEN deaths > deaths0 THEN ah0 ELSE max(ah, coalesce(ah0, 0)) END AS ah,
        CASE WHEN deaths > deaths0 THEN ac0 ELSE max(ac, coalesce(ac0, 0)) END AS ac,
        CASE WHEN deaths > deaths0 THEN an0 ELSE max(an, coalesce(an0, 0)) END AS an,
        CASE WHEN deaths > deaths0 THEN at0 ELSE max("at", coalesce(at0, 0)) END AS "at"
    FROM pr WHERE deaths > deaths0 OR (t - t0 <= 1.5 AND hp < hp0 AND coalesce(deaths, 0) = coalesce(deaths0, 0))
),
e AS (
    SELECT r.*, r.hc IS NOT NULL AS api,
        EXISTS (SELECT 1 FROM tw WHERE tw.team = 5 - l.team AND (tw.x - r.x) * (tw.x - r.x) + (tw.y - r.y) * (tw.y - r.y) <= 750 * 750) AS near_tower,
        EXISTS (SELECT 1 FROM camps c WHERE (c.x - r.x) * (c.x - r.x) + (c.y - r.y) * (c.y - r.y) <= 600 * 600) AS near_camp,
        coalesce((SELECT min(min((f.topx - r.x) * (f.topx - r.x) + (f.topy - r.y) * (f.topy - r.y),
                                 (f.midx - r.x) * (f.midx - r.x) + (f.midy - r.y) * (f.midy - r.y),
                                 (f.botx - r.x) * (f.botx - r.x) + (f.boty - r.y) * (f.boty - r.y)))
                  FROM ev_front f WHERE f.game_id = r.game_id AND f.t > r.t - 1.5 AND f.t <= r.t + 0.5 AND f.team = 5 - l.team) <= 520 * 520, 0) AS near_front
    FROM r LEFT JOIN lineup l ON l.game_id = r.game_id AND l.pid = r.pid
)
SELECT game_id, pid, t, x, y, died, loss, loss_hp,
    CASE WHEN api THEN 'api' ELSE 'inferred' END AS basis,
    coalesce(nullif(ltrim(CASE WHEN api THEN
            CASE WHEN hit THEN '+hero' ELSE '' END
            || CASE WHEN ht THEN '+tower' ELSE '' END
            || CASE WHEN hc AND ac > 0 THEN '+creep' ELSE '' END
            || CASE WHEN an > 0 AND (hc OR NOT (hit OR ht)) THEN '+neutral' ELSE '' END
            || CASE WHEN hc AND ac = 0 AND an = 0 THEN '+unit' ELSE '' END
        ELSE
            CASE WHEN hit THEN '+hero' ELSE '' END
            || CASE WHEN near_tower THEN '+tower?' ELSE '' END
            || CASE WHEN near_front THEN '+creep?' ELSE '' END
            || CASE WHEN near_camp THEN '+neutral?' ELSE '' END
        END, '+'), ''), 'unexplained') AS src,
    hit, hc, ht, ah, ac, an, "at", near_tower, near_front, near_camp
FROM e
