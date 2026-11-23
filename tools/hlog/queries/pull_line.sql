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
-- The wanted wave's own creeps (logs from team-bots c87cd648 on; 0 in older ones): each wanted slot's wave, by the pulling
-- team's ev=wave_creep_death (every own lane creep's death, anywhere) whose lane is the slot's and whose born second falls in
-- the slot's wave (floor(born / 30) = floor((slot - 1) / 30)), however long after the slot it died. Who took each: the other
-- team's creep_death of the same kind within 1 s and 250 units, mutual nearest (`seen`, unwindowed); else our deny from
-- its own `by`; else `other`. Off the line's window, so overlapping windows do not merge two waves.
--   w_n all of them; w_lh the other team's last hits (the named line is w_lh / w_n); w_lh_core those by its pos 1-3; w_deny
--   ours; w_tower no hero and their tower on it; w_other the rest (neutrals, creeps, spells, nobody of theirs near);
--   w_camp those that died within 700 of a neutral camp's spawn point (`judgement`: no lane death came within 1,000 in the wave line's smoke, 0bfb851e, pulls off), any fate.
--   A line over half health is counted (a creep killed from there in one frame, or, rarely, a change of owner).
-- The window ledger (o_*, e_*) predates the wave line: :lead 15 with :win 55 was its nearest to the wanted wave's creeps.
-- ensure: ev_choice(pid, kind, want, lane, slot)
-- ensure: ev_pull_job(pid, lane, slot, res, hit, div, dt)
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- ensure: ev_bot(pid, team, pos)
-- ensure: ev_wave_creep_death(team, kind, x, y, by, lane, born)
WITH
-- include: camp_spawns
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
-- The wanted waves' own creeps, and each one's sighting in the other team's log (`sw`: creep_death unwindowed).
wc AS MATERIALIZED (
    SELECT w.game_id, w.seq, w.t, w.team AS owner, w.kind, w.x, w.y, CAST(w."by" AS TEXT) AS who, ws.slot, ws.lane
    FROM ev_wave_creep_death w
    JOIN ws ON ws.game_id = w.game_id AND ws.team = w.team
        AND ws.lane = CASE w.lane WHEN 'top' THEN 1 WHEN 'mid' THEN 2 WHEN 'bot' THEN 3 END
        AND ws.wave = CAST(w.born / 30 AS INTEGER)
    WHERE w.born IS NOT NULL
),
sw AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, 5 - c.team AS owner, c.kind, c.x, c.y, CAST(c."by" AS TEXT) AS who, coalesce(c.tw, 0) AS tw
    FROM ev_creep_death c WHERE c.team IN (2, 3) AND c.game_id IN (SELECT game_id FROM wc)
),
wpair AS MATERIALIZED (
    SELECT * FROM (
        SELECT w.game_id, w.seq AS wseq, s.who, s.tw,
            row_number() OVER (PARTITION BY w.game_id, w.seq ORDER BY (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y), abs(s.t - w.t), s.seq) AS rw,
            row_number() OVER (PARTITION BY s.game_id, s.seq ORDER BY (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y), abs(s.t - w.t), w.seq) AS rs
        FROM wc w JOIN sw s ON s.game_id = w.game_id AND s.owner = w.owner AND s.kind = w.kind
            AND s.t BETWEEN w.t - 1 AND w.t + 1 AND (s.x - w.x) * (s.x - w.x) + (s.y - w.y) * (s.y - w.y) <= 62500
    ) WHERE rw = 1 AND rs = 1
),
wfate AS (
    SELECT w.game_id, w.owner AS team, w.lane,
        CASE WHEN p.who IS NOT NULL AND p.who NOT IN ('none', 'deny') THEN 'lh'
             WHEN w.who <> 'none' OR p.who = 'deny' THEN 'deny'
             WHEN p.tw = 1 THEN 'tower' ELSE 'other' END AS fate,
        (SELECT b.pos FROM tm b WHERE b.game_id = w.game_id AND CAST(b.pid AS TEXT) = p.who) AS pos,
        EXISTS (SELECT 1 FROM camps k WHERE (k.x - w.x) * (k.x - w.x) + (k.y - w.y) * (k.y - w.y) <= 490000) AS camp
    FROM wc w LEFT JOIN wpair p ON p.game_id = w.game_id AND p.wseq = w.seq
),
wave_ledger AS (
    SELECT game_id, team, lane, count(*) AS w_n, sum(fate = 'lh') AS w_lh, sum(fate = 'lh' AND pos BETWEEN 1 AND 3) AS w_lh_core,
        sum(fate = 'deny') AS w_deny, sum(fate = 'tower') AS w_tower, sum(fate = 'other') AS w_other, sum(camp) AS w_camp
    FROM wfate GROUP BY 1, 2, 3
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
    coalesce(l.e_tower, 0) AS e_tower, coalesce(l.e_other, 0) AS e_other,
    coalesce(v.w_n, 0) AS w_n, coalesce(v.w_lh, 0) AS w_lh, coalesce(v.w_lh_core, 0) AS w_lh_core, coalesce(v.w_deny, 0) AS w_deny,
    coalesce(v.w_tower, 0) AS w_tower, coalesce(v.w_other, 0) AS w_other, coalesce(v.w_camp, 0) AS w_camp
FROM funnel f JOIN gm g ON g.game_id = f.game_id
LEFT JOIN ledger l ON l.game_id = f.game_id AND l.team = f.team AND l.lane = f.lane
LEFT JOIN wave_ledger v ON v.game_id = f.game_id AND v.team = f.team AND v.lane = f.lane
ORDER BY g.file, f.team, f.lane
