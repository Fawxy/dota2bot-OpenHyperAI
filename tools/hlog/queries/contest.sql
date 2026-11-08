-- The contest walk-in (Ours.CoreContest; states/contest) in games whose file matches :like, before
-- :until (default 600). One row per bot with a walk-in (ev=lh cw=1) or a refusal (ev=contest_skip): `walkins`, `landed`
-- (result ok), `retarget` (interrupted, msg sw=1: the pick went for a creep killable now), `released` (interrupted, sw=0:
-- the price failed mid-walk), `leash` (interrupted with no sw: the leash or the body's stop), `taken` (taken_by_other),
-- `denied`, `other` (timeout, missed, ...); `rate` = landed / walkins (the per-attempt target), `rate_nosw` without the
-- retargets; `dh_mean`, `dh_max` (HP-% lost pick to end; negative = gained, a level-up), `cc_mean` (priced HP-%), and the
-- refusals by place and reason (`pick_cost`, `pick_two`, `pick_hp`, `pick_tower`, `walk_cost`, `walk_two`, `walk_hp`,
-- `walk_tower`).
-- ensure: ev_lh(pid, kind, result, reason, cw, cc, dh, msg)
-- ensure: ev_contest_skip(pid, at, why)
-- ensure: ev_bot(pid, hero)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
w AS (
    SELECT l.game_id, l.pid,
        count(*) AS walkins,
        sum(l.result = 'ok') AS landed,
        sum(l.reason = 'interrupted' AND l.msg LIKE '%sw=1%') AS retarget,
        sum(l.reason = 'interrupted' AND l.msg LIKE '%sw=0%') AS released,
        sum(l.reason = 'interrupted' AND l.msg NOT LIKE '%sw=%') AS leash,
        sum(l.reason = 'taken_by_other') AS taken,
        sum(l.reason = 'denied') AS denied,
        sum(l.result <> 'ok' AND l.reason NOT IN ('interrupted', 'taken_by_other', 'denied')) AS other,
        avg(l.dh) AS dh_mean, max(l.dh) AS dh_max, avg(l.cc) AS cc_mean
    FROM ev_lh l
    WHERE l.game_id IN (SELECT game_id FROM gm) AND l.cw = 1 AND l.t <= coalesce(:until, 600)
    GROUP BY 1, 2
),
k AS (
    SELECT game_id, pid,
        sum(at = 'pick' AND why = 'cost') AS pick_cost, sum(at = 'pick' AND why = 'two') AS pick_two,
        sum(at = 'pick' AND why = 'hp') AS pick_hp, sum(at = 'pick' AND why = 'tower') AS pick_tower,
        sum(at = 'walk' AND why = 'cost') AS walk_cost, sum(at = 'walk' AND why = 'two') AS walk_two,
        sum(at = 'walk' AND why = 'hp') AS walk_hp, sum(at = 'walk' AND why = 'tower') AS walk_tower
    FROM ev_contest_skip
    WHERE game_id IN (SELECT game_id FROM gm) AND t <= coalesce(:until, 600)
    GROUP BY 1, 2
),
ids AS (SELECT game_id, pid FROM w UNION SELECT game_id, pid FROM k)
SELECT gm.file, ids.game_id AS game, ids.pid,
    (SELECT max(b.hero) FROM ev_bot b WHERE b.game_id = ids.game_id AND b.pid = ids.pid) AS hero,
    coalesce(w.walkins, 0) AS walkins, coalesce(w.landed, 0) AS landed, coalesce(w.retarget, 0) AS retarget,
    coalesce(w.released, 0) AS released, coalesce(w.leash, 0) AS leash, coalesce(w.taken, 0) AS taken,
    coalesce(w.denied, 0) AS denied, coalesce(w.other, 0) AS other,
    round(1.0 * w.landed / nullif(w.walkins, 0), 2) AS rate,
    round(1.0 * w.landed / nullif(w.walkins - w.retarget, 0), 2) AS rate_nosw,
    round(w.dh_mean, 1) AS dh_mean, w.dh_max, round(w.cc_mean, 1) AS cc_mean,
    coalesce(k.pick_cost, 0) AS pick_cost, coalesce(k.pick_two, 0) AS pick_two, coalesce(k.pick_hp, 0) AS pick_hp,
    coalesce(k.pick_tower, 0) AS pick_tower, coalesce(k.walk_cost, 0) AS walk_cost, coalesce(k.walk_two, 0) AS walk_two,
    coalesce(k.walk_hp, 0) AS walk_hp, coalesce(k.walk_tower, 0) AS walk_tower
FROM ids
JOIN gm ON gm.game_id = ids.game_id
LEFT JOIN w ON w.game_id = ids.game_id AND w.pid = ids.pid
LEFT JOIN k ON k.game_id = ids.game_id AND k.pid = ids.pid
ORDER BY gm.file, ids.game_id, ids.pid;
