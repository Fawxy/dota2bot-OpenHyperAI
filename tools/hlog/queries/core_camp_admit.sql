-- Refusal precision (slice core-next-gold, review 2026-11-10-core-price-plan): in a drill run with Overrides.AdmitLog the
-- trip's price check at the camp logs its verdict (`phase=admit`, `v` hp, time or ok) and refuses nobody, so every camp the
-- rule would have refused is cleared and its outcome is seen. One row per admit line in games whose file matches :like.
--   dmg     the HP lost to damage from the check to a second past the last neutral kill by the core (or the trip's end)
--   breach  1 when the core's HP at the check less dmg is under ArriveHP (:arrive, default 0.4): the clear cost more than the rule allows
--   late    1 when the clear ran past the latest leave the check logged (`lb`: the last neutral kill, or the trip's end, after it) or
--           was left at a deadline with neutrals left (`nl` above 0 and not cut by a retreat, `preempted`, or the HP abort)
--   One row per camp: the engage verdict (the last admit line of the trip's camp); the check at first sight often sees half the camp.
-- A would-refuse row that breached or ended late was a good refusal; one that did not was a camp the rule lost.
-- ensure: ev_core_camp(pid, phase, v, hp, hpe, clre, lb, nl, why)
-- ensure: ev_neutral_death(by)
-- ensure: ev_snap(pid, hp)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
ad AS (
    SELECT a.game_id, a.pid, a.t, a.camp, a.src, a.v, a.hp, a.hpe, a.clre, a.lb,
        (SELECT min(e.t) FROM ev_core_camp e WHERE e.game_id = a.game_id AND e.pid = a.pid AND e.phase = 'end' AND e.t >= a.t) AS t1
    FROM ev_core_camp a JOIN gm ON gm.game_id = a.game_id WHERE a.phase = 'admit'
),
last AS (
    SELECT ad.*, row_number() OVER (PARTITION BY ad.game_id, ad.pid, ad.camp, ad.t1 ORDER BY ad.t DESC) AS rn FROM ad
),
k AS (
    SELECT ad.*, coalesce((SELECT max(d.t) FROM ev_neutral_death d WHERE d.game_id = ad.game_id AND CAST(d.by AS TEXT) = CAST(ad.pid AS TEXT)
            AND d.t >= ad.t AND d.t <= ad.t1), ad.t1) AS tk,
        (SELECT e.why FROM ev_core_camp e WHERE e.game_id = ad.game_id AND e.pid = ad.pid AND e.phase = 'end' AND e.t = ad.t1) AS why,
        (SELECT e.nl FROM ev_core_camp e WHERE e.game_id = ad.game_id AND e.pid = ad.pid AND e.phase = 'end' AND e.t = ad.t1) AS nl
    FROM last ad WHERE ad.rn = 1
)
SELECT gm.file, k.game_id, k.pid, round(k.t, 1) AS t, k.camp, k.src, k.v, k.hp, round(k.hpe, 2) AS hpe, round(k.clre, 1) AS clre, round(k.lb, 1) AS lb, round(k.tk, 1) AS tk, k.nl, k.why,
    round((SELECT sum(CASE WHEN d > 0 THEN d ELSE 0 END) / 100.0 FROM (
        SELECT lag(s.hp) OVER (ORDER BY s.t) - s.hp AS d FROM ev_snap s
        WHERE s.game_id = k.game_id AND s.pid = k.pid AND s.t >= k.t AND s.t <= k.tk + 1)), 2) AS dmg,
    CASE WHEN k.hp - (SELECT sum(CASE WHEN d > 0 THEN d ELSE 0 END) / 100.0 FROM (
        SELECT lag(s.hp) OVER (ORDER BY s.t) - s.hp AS d FROM ev_snap s
        WHERE s.game_id = k.game_id AND s.pid = k.pid AND s.t >= k.t AND s.t <= k.tk + 1)) < coalesce(:arrive, 0.4) THEN 1 ELSE 0 END AS breach,
    CASE WHEN (k.lb IS NOT NULL AND k.tk > k.lb + 1) OR (coalesce(k.nl, 0) > 0 AND coalesce(k.why, '') NOT LIKE 'preempted%' AND coalesce(k.why, '') NOT LIKE 'interrupted%') THEN 1 ELSE 0 END AS late
FROM k JOIN gm ON gm.game_id = k.game_id
ORDER BY k.game_id, k.t, k.pid;
