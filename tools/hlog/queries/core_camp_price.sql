-- The camp trip's price graded on one truth (slice core-next-gold, CoreCamp, review 2026-11-10-core-price-plan): one row per
-- finished clear with the model's price at engage (`hpe`, before the learned rate; `clre`) in games whose file matches :like.
--   pred   hpe x hpr, the live price with the learned rate;   tbl  the type table's price (`hpt` of the trip's start line)
--   dmg    the truth: the HP the core lost to damage during the clear, the sum of the drops between its snapshots (regen and
--          lifesteal do not count, unlike `hpm`, the net change), from the engage (the last neutral kill less the measured
--          clear `clrm`) to a second past the last kill. The kill time is the clear's end to a second; a snapshot is about a second.
--   err    pred - dmg and terr  tbl - dmg (signed: positive over-prices)
--   Finished clears only (no neutral left, `nl` 0): the price is of the whole camp, `dmg` of the clear as far as it went, so an
--   unfinished one (cut by a retreat, `interrupted`, a deadline) reads low. :all = 1 lists them too, with `nl`. A clear in which the
--   core killed nothing stays (its window is the measured clear before the trip's end, which includes the walk back).
-- ensure: ev_core_camp(pid, phase, hpe, hpr, clre, clrm, hpm, hpt, src, type, nl)
-- ensure: ev_neutral_death(by)
-- ensure: ev_snap(pid, hp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
en AS (
    SELECT e.game_id, e.pid, e.t AS t1, e.hpe, e.hpr, e.clre, e.clrm, e.hpm, e.nl,
        coalesce((SELECT max(d.t) FROM ev_neutral_death d WHERE d.game_id = e.game_id AND CAST(d.by AS TEXT) = CAST(e.pid AS TEXT)
            AND d.t <= e.t AND d.t >= e.t - e.clrm - 40), e.t) AS tk
    FROM ev_core_camp e JOIN gm ON gm.game_id = e.game_id
    WHERE e.phase = 'end' AND e.hpe IS NOT NULL AND e.clrm IS NOT NULL AND (coalesce(e.nl, 0) = 0 OR coalesce(:all, 0) = 1)
),
k AS (
    SELECT en.*, (SELECT sum(CASE WHEN d > 0 THEN d ELSE 0 END) / 100.0 FROM (
        SELECT lag(s.hp) OVER (ORDER BY s.t) - s.hp AS d FROM ev_snap s
        WHERE s.game_id = en.game_id AND s.pid = en.pid AND s.t >= en.tk - en.clrm - 1 AND s.t <= en.tk + 1)) AS dmg,
        (SELECT x.hpt FROM ev_core_camp x WHERE x.game_id = en.game_id AND x.pid = en.pid AND x.phase IN ('start', 'next') AND x.t <= en.t1
            ORDER BY x.t DESC LIMIT 1) AS tbl,
        (SELECT x.src FROM ev_core_camp x WHERE x.game_id = en.game_id AND x.pid = en.pid AND x.phase IN ('start', 'next') AND x.t <= en.t1
            ORDER BY x.t DESC LIMIT 1) AS src
    FROM en
)
SELECT gm.file, k.game_id, k.pid, round(k.t1, 1) AS t, k.src, round(k.hpe, 2) AS hpe, k.hpr, round(k.hpe * k.hpr, 2) AS pred,
    k.tbl, round(k.dmg, 2) AS dmg, k.hpm, k.nl,
    round(k.hpe * k.hpr - k.dmg, 2) AS err, round(k.tbl - k.dmg, 2) AS terr
FROM k JOIN gm ON gm.game_id = k.game_id
ORDER BY k.game_id, k.t1;
