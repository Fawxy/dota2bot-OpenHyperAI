-- Who got each lane creep that died near a hero, both sides, one row per logged death (slice creep-economy, KR L.1).
-- `side` = 'enemy' (an enemy creep that died near the logging team's heroes: ev=creep_death) or 'own' (a creep of the
-- logging team that died near its heroes: ev=own_creep_death). `team` is the logging team; `pid` the hero credited.
-- fate, enemy side: own_lh (an own hero's last hit, pid), enemy_deny (an enemy hero denied it: the other team's own_creep_death
--   with a denier, same kind, within 1 s and 250 units, nearest pair first, each death used once; pid = the enemy denier),
--   other (tower, creep, a spell the counters do not see, or a death the other team did not log).
-- fate, own side: own_deny (an own hero denied it, pid), lost (anything else: an enemy last hit, tower or creep kill).
-- Enemy denies exist only here: ev=creep_death `by=deny` never fires (an enemy hero's GetDenies reads 0), so those deaths
-- are by=none in the log and are named by the denier's own team log. A creep is in both teams' logs when each had a hero near;
-- count one side of one team per question. Positions are the last frame seen, so a pair can lie a little apart: 250 is wide
-- enough for a frame at 8x and narrow enough that two creeps of one kind in a wave rarely compete.
-- ensure: ev_creep_death(team, kind, x, y, by)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
WITH cand AS (
    SELECT c.game_id, c.seq AS cseq, o.seq AS oseq, o."by" AS denier,
        abs(o.t - c.t) AS dt, (o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y) AS d2
    FROM ev_creep_death c
    JOIN ev_own_creep_death o ON o.game_id = c.game_id AND o.team <> c.team AND o.kind = c.kind
        AND abs(o.t - c.t) <= 1.0
        AND (o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y) <= 62500
    WHERE CAST(c."by" AS TEXT) = 'none' AND CAST(o."by" AS TEXT) <> 'none'
),
by_c AS (
    SELECT *, row_number() OVER (PARTITION BY game_id, cseq ORDER BY d2, dt, oseq) AS rc FROM cand
),
by_o AS (
    SELECT *, row_number() OVER (PARTITION BY game_id, oseq ORDER BY d2, dt, cseq) AS ro FROM by_c WHERE rc = 1
),
pairs AS (
    SELECT game_id, cseq, denier FROM by_o WHERE ro = 1
)
SELECT c.game_id, c.seq, c.t, c.team, 'enemy' AS side, c.kind, c.x, c.y,
    CASE WHEN CAST(c."by" AS TEXT) NOT IN ('none', 'deny') THEN 'own_lh'
         WHEN p.cseq IS NOT NULL THEN 'enemy_deny'
         ELSE 'other' END AS fate,
    CASE WHEN CAST(c."by" AS TEXT) NOT IN ('none', 'deny') THEN c."by" ELSE p.denier END AS pid
FROM ev_creep_death c
LEFT JOIN pairs p ON p.game_id = c.game_id AND p.cseq = c.seq
UNION ALL
SELECT o.game_id, o.seq, o.t, o.team, 'own', o.kind, o.x, o.y,
    CASE WHEN CAST(o."by" AS TEXT) <> 'none' THEN 'own_deny' ELSE 'lost' END,
    CASE WHEN CAST(o."by" AS TEXT) <> 'none' THEN o."by" END
FROM ev_own_creep_death o
