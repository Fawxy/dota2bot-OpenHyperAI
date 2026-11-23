-- ROADMAP 8a's line and its ledger (plan s5): per game, team and lane, every lane creep that died in the :win seconds
-- (default 75; from :lead seconds after the slot, default 0) from a slot that team's pull trigger wanted (ev=choice kind=pull want=1: the pulling team's own line or a
-- switched-off team's src=shadow line), both sides, by who took it. Games whose file matches :like.
-- A wanted slot is one per team, lane and pulled wave (floor((slot - 1) / 30): the two arms read one wave at different
-- seconds), with slot < :to (default 525, so a window ends by 10:00). Windows of consecutive slots overlap, so a death
-- counts once per team and lane, when it falls in any of them. :first = 1 keeps only each team and lane's first wanted slot
-- (where the arms of a pair have not yet diverged).
-- A death's lane is read from where it died: y - x over 4,000 top (1), under -4,000 bot (3), else mid (2); a side lane's
-- pull camps lie on its side of those lines, so a pulled wave counts where it died.
-- Our creeps (the team's own), from both logs: the other team's ev=creep_death (its heroes within 1,500) and our
-- ev=own_creep_death (ours within 1,500), one death when the two agree on kind within 1 s and 250 units.
--   o_dead all of them; o_lh the other team's last hits (the named line is o_lh / o_dead); o_lh_core those by its pos 1-3;
--   o_deny our denies; o_tower no hero and their tower on it the frame before; o_other the rest (creeps, neutrals, spells,
--   nobody near).
-- Their creeps, the same way round: e_dead; e_lh our last hits, e_lh_core by our pos 1-3; e_deny their denies; e_tower our
--   tower's; e_other.
-- The funnel: wanted slots; started (an ev=pull_job of that team and lane on the slot's wave); hit (its hit=1); diverted (res
--   ok and dt, or div where a line has no dt, at least 0.75, as view pull_attempts); first_slot the first wanted slot.
-- A creep that died with no hero of either team within 1,500 is in neither log.
-- No death line says which wave a creep came from, so the wanted wave's own creeps cannot be picked out. :lead 15 with
-- :win 55 is the nearest the logs give: a diverted wave dies at its camp from about 15 to 55 s after the slot (pullrow1), and
-- an unpulled one reaches the lane's fight in about that time; the window still holds about a wave and a third.
-- ensure: ev_choice(pid, kind, want, lane, slot)
-- ensure: ev_pull_job(pid, lane, slot, res, hit, div, dt)
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_bot(pid, team, pos)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot WHERE team IS NOT NULL AND game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
wanted AS MATERIALIZED (
    SELECT c.game_id, tm.team, c.lane, CAST((c.slot - 1) / 30 AS INTEGER) AS wave, min(c.slot) AS slot
    FROM ev_choice c JOIN tm ON tm.game_id = c.game_id AND tm.pid = c.pid
    WHERE c.kind = 'pull' AND c.want = 1 AND c.slot < coalesce(:to, 525)
    GROUP BY 1, 2, 3, 4
),
ws AS MATERIALIZED (
    SELECT * FROM (SELECT w.*, row_number() OVER (PARTITION BY game_id, team, lane ORDER BY slot) AS rn FROM wanted w)
    WHERE coalesce(:first, 0) <> 1 OR rn = 1
),
jobs AS MATERIALIZED (
    SELECT j.game_id, tm.team, j.lane, CAST((j.slot - 1) / 30 AS INTEGER) AS wave, max(coalesce(j.hit, 0)) AS hit,
        max(j.res = 'ok' AND coalesce(j.dt, j.div) >= 0.75) AS diverted
    FROM ev_pull_job j JOIN tm ON tm.game_id = j.game_id AND tm.pid = j.pid
    GROUP BY 1, 2, 3, 4
),
funnel AS (
    SELECT w.game_id, w.team, w.lane, count(*) AS wanted, count(j.wave) AS started, coalesce(sum(j.hit), 0) AS hit,
        coalesce(sum(j.diverted), 0) AS diverted, min(w.slot) AS first_slot
    FROM ws w LEFT JOIN jobs j ON j.game_id = w.game_id AND j.team = w.team AND j.lane = w.lane AND j.wave = w.wave
    GROUP BY 1, 2, 3
),
-- A creep as the other team saw it die: `owner` the creep's team, `taker` the logging team.
seen AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, 5 - c.team AS owner, c.kind, c.x, c.y, CAST(c."by" AS TEXT) AS who, coalesce(c.tw, 0) AS tw
    FROM ev_creep_death c JOIN gm ON gm.game_id = c.game_id
    WHERE c.team IN (2, 3) AND c.t < coalesce(:to, 525) + coalesce(:win, 75)
),
own AS MATERIALIZED (
    SELECT o.game_id, o.seq, o.t, o.team AS owner, o.kind, o.x, o.y, CAST(o."by" AS TEXT) AS who
    FROM ev_own_creep_death o JOIN gm ON gm.game_id = o.game_id
    WHERE o.team IN (2, 3) AND o.t < coalesce(:to, 525) + coalesce(:win, 75)
),
-- Each deny in the owner's log names the one death in the other log nearest to it (a wave's creeps die close together).
denied AS MATERIALIZED (
    SELECT game_id, sseq FROM (
        SELECT o.game_id, s.seq AS sseq, row_number() OVER (PARTITION BY o.game_id, o.seq
            ORDER BY (s.x - o.x) * (s.x - o.x) + (s.y - o.y) * (s.y - o.y), abs(s.t - o.t), s.seq) AS rn
        FROM own o JOIN seen s ON s.game_id = o.game_id AND s.owner = o.owner AND s.kind = o.kind AND s.who = 'none'
            AND s.t BETWEEN o.t - 1 AND o.t + 1 AND (s.x - o.x) * (s.x - o.x) + (s.y - o.y) * (s.y - o.y) <= 62500
        WHERE o.who <> 'none'
    ) WHERE rn = 1
),
dead AS MATERIALIZED (
    SELECT s.game_id, s.t, s.owner, s.x, s.y,
        CASE WHEN s.who NOT IN ('none', 'deny') THEN 'lh'
             WHEN s.who = 'deny' OR EXISTS (SELECT 1 FROM denied p WHERE p.game_id = s.game_id AND p.sseq = s.seq) THEN 'deny'
             WHEN s.tw = 1 THEN 'tower' ELSE 'other' END AS fate,
        CASE WHEN s.who NOT IN ('none', 'deny') THEN s.who END AS pid
    FROM seen s
    UNION ALL
    SELECT o.game_id, o.t, o.owner, o.x, o.y, CASE WHEN o.who <> 'none' THEN 'deny' ELSE 'other' END, NULL
    FROM own o
    WHERE NOT EXISTS (SELECT 1 FROM seen s WHERE s.game_id = o.game_id AND s.owner = o.owner AND s.kind = o.kind
        AND s.t BETWEEN o.t - 1 AND o.t + 1 AND (s.x - o.x) * (s.x - o.x) + (s.y - o.y) * (s.y - o.y) <= 62500)
),
inwin AS (
    SELECT f.game_id, f.team, f.lane, d.owner, d.fate,
        (SELECT b.pos FROM tm b WHERE b.game_id = d.game_id AND CAST(b.pid AS TEXT) = d.pid) AS pos
    FROM funnel f JOIN dead d ON d.game_id = f.game_id
        AND CASE WHEN d.y - d.x > 4000 THEN 1 WHEN d.y - d.x < -4000 THEN 3 ELSE 2 END = f.lane
    WHERE EXISTS (SELECT 1 FROM ws w WHERE w.game_id = f.game_id AND w.team = f.team AND w.lane = f.lane
        AND d.t >= w.slot + coalesce(:lead, 0) AND d.t < w.slot + coalesce(:win, 75))
),
ledger AS (
    SELECT game_id, team, lane,
        sum(owner = team) AS o_dead,
        sum(owner = team AND fate = 'lh') AS o_lh,
        sum(owner = team AND fate = 'lh' AND pos BETWEEN 1 AND 3) AS o_lh_core,
        sum(owner = team AND fate = 'deny') AS o_deny,
        sum(owner = team AND fate = 'tower') AS o_tower,
        sum(owner = team AND fate = 'other') AS o_other,
        sum(owner <> team) AS e_dead,
        sum(owner <> team AND fate = 'lh') AS e_lh,
        sum(owner <> team AND fate = 'lh' AND pos BETWEEN 1 AND 3) AS e_lh_core,
        sum(owner <> team AND fate = 'deny') AS e_deny,
        sum(owner <> team AND fate = 'tower') AS e_tower,
        sum(owner <> team AND fate = 'other') AS e_other
    FROM inwin GROUP BY 1, 2, 3
)
SELECT f.game_id, g.file, f.team, f.lane, f.wanted, f.started, f.hit, f.diverted, f.first_slot,
    coalesce(l.o_dead, 0) AS o_dead, coalesce(l.o_lh, 0) AS o_lh, coalesce(l.o_lh_core, 0) AS o_lh_core, coalesce(l.o_deny, 0) AS o_deny,
    coalesce(l.o_tower, 0) AS o_tower, coalesce(l.o_other, 0) AS o_other,
    coalesce(l.e_dead, 0) AS e_dead, coalesce(l.e_lh, 0) AS e_lh, coalesce(l.e_lh_core, 0) AS e_lh_core, coalesce(l.e_deny, 0) AS e_deny,
    coalesce(l.e_tower, 0) AS e_tower, coalesce(l.e_other, 0) AS e_other
FROM funnel f JOIN gm g ON g.game_id = f.game_id
LEFT JOIN ledger l ON l.game_id = f.game_id AND l.team = f.team AND l.lane = f.lane
ORDER BY g.file, f.team, f.lane
