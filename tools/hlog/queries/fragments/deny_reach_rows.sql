-- Fragment (`-- include: deny_reach_rows`): the lane denies line's rows (family lane denies, master
-- docs/proposals/2026-11-24-next-three-families.md s6), one definition for views deny_reach and deny_reach_games. The including
-- query defines `gm(game_id, file, game)` first. CTE `deny_reach_rows(game_id, seq, t, team, kind, x, y, pid, pos, ln, dist, ar,
-- offers, band, fate)`. Ends with a comma.
--   unit    an own lane creep's death as its owner logged it (ev=own_creep_death: 50% HP or less, within 1,500 of an own hero, to
--           :until, default 600) with a pos 4 or 5 of its team alive in a side lane (snap `ln` top or bot) at that support's
--           last snapshot in the 1.5 s before the death. Found from places and deaths, never from our own read: the same rule on
--           both arms and on stock.
--   band    `in` when the support was within its attack range + 48 (hull slack, telemetry RANGE_SLACK) + 300 (lane_offers
--           MAX_WALK, 1 s, at about 300 move speed: `judgement`, move speed is not logged) of the creep; `near` to range + 648
--           (a second walk more): just outside reach, an outcome count to grade a wider reach later (user 24/11/2026). The
--           nearer of the two supports names the row.
--   fate    `sup_deny` the row's support denied it; `own_deny` another own hero did; `enemy_lh` the other team's creep_death of
--           the same kind within 1 s and 250 names an enemy last hitter (its nearest such row; not the mutual pairing of view
--           creep_fate); `other` a tower, a creep, or not attributable.
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_creep_death(team, kind, x, y, by)
-- ensure: ev_snap(pid, x, y, alive, ar, od, ln)
-- ensure: ev_bot(pid, team, pos, hero)
dr_hb AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot
    WHERE game_id IN (SELECT game_id FROM gm) GROUP BY game_id, pid),
dr_own AS MATERIALIZED (
    SELECT o.game_id, o.seq, o.t, o.team, o.kind, o.x, o.y, CAST(o."by" AS TEXT) AS dby FROM ev_own_creep_death o
    WHERE o.game_id IN (SELECT game_id FROM gm) AND o.t < coalesce(:until, 600)
),
dr_en AS MATERIALIZED (
    SELECT c.game_id, c.t, c.team, c.kind, c.x, c.y, CAST(c."by" AS TEXT) AS lby FROM ev_creep_death c
    WHERE c.game_id IN (SELECT game_id FROM gm) AND c.t < coalesce(:until, 600) + 2
),
dr_sup AS (
    SELECT d.game_id, d.seq, b.pid, b.pos,
        (SELECT s.seq FROM ev_snap s WHERE s.game_id = d.game_id AND s.pid = b.pid AND s.t BETWEEN d.t - 1.5 AND d.t
            ORDER BY s.t DESC LIMIT 1) AS sseq
    FROM dr_own d JOIN dr_hb b ON b.game_id = d.game_id AND b.team = d.team AND b.pos IN (4, 5)
),
dr_reach AS (
    SELECT u.game_id, u.seq, u.pid, u.pos, s.ln, s.od AS offers, s.ar,
        sqrt((s.x - d.x) * (s.x - d.x) + (s.y - d.y) * (s.y - d.y)) AS dist
    FROM dr_sup u JOIN dr_own d ON d.game_id = u.game_id AND d.seq = u.seq
    JOIN ev_snap s ON s.game_id = u.game_id AND s.seq = u.sseq
    WHERE s.alive = 1 AND s.ln IN ('top', 'bot') AND s.ar IS NOT NULL
        AND (s.x - d.x) * (s.x - d.x) + (s.y - d.y) * (s.y - d.y) <= (s.ar + 648) * (s.ar + 648)
),
dr_one AS (SELECT *, row_number() OVER (PARTITION BY game_id, seq ORDER BY dist, pid) AS rk FROM dr_reach),
deny_reach_rows AS (
    SELECT d.game_id, d.seq, d.t, d.team, d.kind, d.x, d.y, r.pid, r.pos, r.ln, round(r.dist) AS dist, r.ar, r.offers,
        CASE WHEN r.dist <= r.ar + 348 THEN 'in' ELSE 'near' END AS band,
        CASE WHEN d.dby = CAST(r.pid AS TEXT) THEN 'sup_deny'
             WHEN d.dby <> 'none' THEN 'own_deny'
             WHEN (SELECT e.lby FROM dr_en e
                    WHERE e.game_id = d.game_id AND e.team <> d.team AND e.kind = d.kind AND e.t BETWEEN d.t - 1.0 AND d.t + 1.0
                        AND (e.x - d.x) * (e.x - d.x) + (e.y - d.y) * (e.y - d.y) <= 62500
                    ORDER BY (e.x - d.x) * (e.x - d.x) + (e.y - d.y) * (e.y - d.y) LIMIT 1) NOT IN ('none', 'deny') THEN 'enemy_lh'
             ELSE 'other' END AS fate
    FROM dr_one r JOIN dr_own d ON d.game_id = r.game_id AND d.seq = r.seq
    WHERE r.rk = 1
),
