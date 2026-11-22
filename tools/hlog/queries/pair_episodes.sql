-- Pair episodes (the `fighting-together` proposal (master tag `pre-process-v5`) "Tools"; D10, D19): one row per pair fight, read per side by
-- pair_episodes.js. From ev_snap by whole second (each hero's last snapshot in the second), lineup heroes pos 1-5:
--   hit        a second in which a hero's snapshot `tid` names an enemy lineup hero (the target)
--   fight      one side's attack run on one target (fragment ep_attack); `t0`, `t1` its first and last hit seconds, `t0` up to
--              :until - 12
--   pair       a fight in which, at some hit second, a second hero of the hitting side is alive within 1,200 of the target;
--              only these are rows. `p1` hit at t0 (ties: the lower pid); `p2` the partner, of the side's other heroes ever
--              within 1,200 of the target at a hit second: the first to hit it, else the first in reach (ties: lower pid)
--   gap2       p2's first hit minus t0 (null: p2 never hit it); `members` the distinct heroes that hit the target
--   split      1 when p1 or p2 hit another enemy hero in [t0, t1]
--   last1/2    each one's last hit on the target in the fight; `ret1/2` its first second in mode retreat in [t0, t1 + 5]
--   minhp      the target's lowest HP in [t0, t1]; `hp0` at t0; `en` the target's side alive within 1,200 of it at t0 (it
--              included), `al` the hitting side's
--   tdied      the target has a ledger death (fragment core_death, pos 1-5, before :until) in [t0, t1 + 12]; `d1`, `d2` p1, p2
-- Params: like (a path fragment), until (720 in pair_episodes.js; the fragment's default is 600).
-- ensure: ev_snap(pid, t, tid, hp, alive, mode, x, y, deaths)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
ep_win AS (SELECT -1e9 AS lo, coalesce(:until, 600) + 0.5 AS hi),
-- include: core_death
-- include: ep_attack
hs AS MATERIALIZED (SELECT game_id, pid, team, pos, sec, x, y, hp, alive, mode, tid FROM ep_sec WHERE pos IS NOT NULL),
hit AS MATERIALIZED (
    SELECT h.game_id, h.apid, h.team, h.sec, h.tpid
    FROM ep_hit h JOIN lineup la ON la.game_id = h.game_id AND la.pid = h.apid JOIN lineup lt ON lt.game_id = h.game_id AND lt.pid = h.tpid
),
fi AS MATERIALIZED (SELECT game_id, team, tpid, t0, t1 FROM ep_run WHERE t0 <= coalesce(:until, 600) - 12),
fh AS MATERIALIZED (
    SELECT fi.game_id, fi.team, fi.tpid, fi.t0, h.apid, h.sec
    FROM fi JOIN hit h ON h.game_id = fi.game_id AND h.team = fi.team AND h.tpid = fi.tpid AND h.sec BETWEEN fi.t0 AND fi.t1
),
p1 AS (SELECT game_id, team, tpid, t0, min(apid) AS p1 FROM fh WHERE sec = t0 GROUP BY game_id, team, tpid, t0),
-- Heroes of the hitting side alive within 1,200 of the target at a hit second, other than that second's hitter.
reach AS MATERIALIZED (
    SELECT DISTINCT fh.game_id, fh.team, fh.tpid, fh.t0, b.pid, fh.sec
    FROM fh JOIN hs tg ON tg.game_id = fh.game_id AND tg.pid = fh.tpid AND tg.sec = fh.sec
    JOIN hs b ON b.game_id = fh.game_id AND b.team = fh.team AND b.sec = fh.sec AND b.pid <> fh.apid AND b.alive = 1
    WHERE (b.x - tg.x) * (b.x - tg.x) + (b.y - tg.y) * (b.y - tg.y) <= 1200 * 1200
),
cand AS (
    SELECT r.game_id, r.team, r.tpid, r.t0, r.pid, min(r.sec) AS inreach,
        (SELECT min(sec) FROM fh WHERE fh.game_id = r.game_id AND fh.team = r.team AND fh.tpid = r.tpid AND fh.t0 = r.t0
            AND fh.apid = r.pid) AS firsthit
    FROM reach r JOIN p1 ON p1.game_id = r.game_id AND p1.team = r.team AND p1.tpid = r.tpid AND p1.t0 = r.t0 AND r.pid <> p1.p1
    GROUP BY r.game_id, r.team, r.tpid, r.t0, r.pid
),
p2 AS (
    SELECT game_id, team, tpid, t0, pid AS p2, firsthit FROM (
        SELECT cand.*, row_number() OVER (PARTITION BY game_id, team, tpid, t0
            ORDER BY firsthit IS NULL, firsthit, inreach, pid) AS rn FROM cand
    ) WHERE rn = 1
),
pe AS MATERIALIZED (
    SELECT fi.game_id, fi.team, fi.tpid, fi.t0, fi.t1, p1.p1, p2.p2, p2.firsthit - fi.t0 AS gap2
    FROM fi JOIN p1 ON p1.game_id = fi.game_id AND p1.team = fi.team AND p1.tpid = fi.tpid AND p1.t0 = fi.t0
    JOIN p2 ON p2.game_id = fi.game_id AND p2.team = fi.team AND p2.tpid = fi.tpid AND p2.t0 = fi.t0
)
SELECT gm.file, pe.game_id, pe.team, pe.tpid, lt.pos AS tpos, pe.t0, pe.t1, pe.p1, l1.pos AS pos1, pe.p2, l2.pos AS pos2, pe.gap2,
    (SELECT count(DISTINCT apid) FROM fh WHERE fh.game_id = pe.game_id AND fh.team = pe.team AND fh.tpid = pe.tpid AND fh.t0 = pe.t0) AS members,
    EXISTS (SELECT 1 FROM hit h WHERE h.game_id = pe.game_id AND h.apid IN (pe.p1, pe.p2) AND h.tpid <> pe.tpid
        AND h.sec BETWEEN pe.t0 AND pe.t1) AS split,
    (SELECT max(sec) FROM fh WHERE fh.game_id = pe.game_id AND fh.team = pe.team AND fh.tpid = pe.tpid AND fh.t0 = pe.t0 AND fh.apid = pe.p1) AS last1,
    (SELECT max(sec) FROM fh WHERE fh.game_id = pe.game_id AND fh.team = pe.team AND fh.tpid = pe.tpid AND fh.t0 = pe.t0 AND fh.apid = pe.p2) AS last2,
    (SELECT min(sec) FROM hs WHERE hs.game_id = pe.game_id AND hs.pid = pe.p1 AND hs.sec BETWEEN pe.t0 AND pe.t1 + 5 AND hs.mode = 'retreat') AS ret1,
    (SELECT min(sec) FROM hs WHERE hs.game_id = pe.game_id AND hs.pid = pe.p2 AND hs.sec BETWEEN pe.t0 AND pe.t1 + 5 AND hs.mode = 'retreat') AS ret2,
    (SELECT min(hp) FROM hs WHERE hs.game_id = pe.game_id AND hs.pid = pe.tpid AND hs.sec BETWEEN pe.t0 AND pe.t1 AND hs.alive = 1) AS minhp,
    tg.hp AS hp0,
    (SELECT count(*) FROM hs o WHERE o.game_id = pe.game_id AND o.sec = pe.t0 AND o.team = tg.team AND o.alive = 1
        AND (o.x - tg.x) * (o.x - tg.x) + (o.y - tg.y) * (o.y - tg.y) <= 1200 * 1200) AS en,
    (SELECT count(*) FROM hs o WHERE o.game_id = pe.game_id AND o.sec = pe.t0 AND o.team = pe.team AND o.alive = 1
        AND (o.x - tg.x) * (o.x - tg.x) + (o.y - tg.y) * (o.y - tg.y) <= 1200 * 1200) AS al,
    EXISTS (SELECT 1 FROM cd WHERE cd.game_id = pe.game_id AND cd.pid = pe.tpid AND cd.t >= pe.t0 AND cd.t <= pe.t1 + 12) AS tdied,
    EXISTS (SELECT 1 FROM cd WHERE cd.game_id = pe.game_id AND cd.pid = pe.p1 AND cd.t >= pe.t0 AND cd.t <= pe.t1 + 12) AS d1,
    EXISTS (SELECT 1 FROM cd WHERE cd.game_id = pe.game_id AND cd.pid = pe.p2 AND cd.t >= pe.t0 AND cd.t <= pe.t1 + 12) AS d2
FROM pe JOIN gm ON gm.game_id = pe.game_id
JOIN lineup lt ON lt.game_id = pe.game_id AND lt.pid = pe.tpid
JOIN lineup l1 ON l1.game_id = pe.game_id AND l1.pid = pe.p1
JOIN lineup l2 ON l2.game_id = pe.game_id AND l2.pid = pe.p2
LEFT JOIN hs tg ON tg.game_id = pe.game_id AND tg.pid = pe.tpid AND tg.sec = pe.t0
ORDER BY gm.file, pe.t0, pe.tpid
