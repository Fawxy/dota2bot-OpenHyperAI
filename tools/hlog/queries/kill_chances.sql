-- Kill chances (ROADMAP row 1 step 1, docs/proposals/2026-11-17-kill-chances.md): one row per hunter-chance, read per side by
-- kill_chances.js. From ev_snap by whole second (each hero's last snapshot in the second), lineup heroes pos 1-5:
--   chance     a hero alive at 40% HP or less with an opposing hero alive at 40% or more within 1,000, at a second up to
--              :until - 12 (708, 11:48, with until 720); one chance per low hero per run of such seconds, a new one after
--              more than 15 s without. `t` is its first second, `x, y` the low hero there.
--   attackers  distinct opposing heroes whose snapshot `tid` names the low hero in [t, t + 8] (any of them, not only hunters)
--   died       1 when the low hero has a ledger death (fragment core_death, pos 1-5, before :until) in [t, t + 12]
--   hunters    the opposing heroes in the chance at its first second, one row each: `hpid`, `hpos`, `hhp`, `dist`;
--              `hatk` 1 when its own `tid` names the low hero in [t, t + 8]; `hmode` its commonest mode in those seconds
--              (ties: the first in name order)
-- Columns: file, game_id, team and pid and pos and hp of the low hero, t, x, y, attackers, died, nh (hunters at t), then the
-- hunter's. Params: like (a path fragment), until (720 in kill_chances.js; the fragment's default is 600).
-- ensure: ev_snap(pid, t, tid, hp, alive, mode, x, y, deaths)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: core_death
hs AS MATERIALIZED (
    SELECT game_id, pid, team, pos, sec, x, y, hp, alive, mode, tid FROM (
        SELECT s.game_id, s.pid, l.team, l.pos, CAST(round(s.t) AS INTEGER) AS sec, s.x, s.y, s.hp, s.alive, s.mode,
            CAST(s.tid AS TEXT) AS tid,
            row_number() OVER (PARTITION BY s.game_id, s.pid, CAST(round(s.t) AS INTEGER) ORDER BY s.seq DESC) AS rn
        FROM gm CROSS JOIN ev_snap s ON s.game_id = gm.game_id CROSS JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
        WHERE s.t <= coalesce(:until, 600) + 0.5 AND s.x IS NOT NULL
    ) WHERE rn = 1
),
-- Seconds a hero is low with at least one hunter: an equality join on the second, then the distance.
pr AS MATERIALIZED (
    SELECT lo.game_id, lo.pid, lo.team, lo.pos, lo.sec, lo.x, lo.y, lo.hp, hu.pid AS hpid, hu.pos AS hpos, hu.hp AS hhp,
        CAST(round(sqrt((hu.x - lo.x) * (hu.x - lo.x) + (hu.y - lo.y) * (hu.y - lo.y))) AS INTEGER) AS dist
    FROM hs lo JOIN hs hu ON hu.game_id = lo.game_id AND hu.sec = lo.sec AND hu.team <> lo.team
    WHERE lo.alive = 1 AND lo.hp > 0 AND lo.hp <= 40 AND hu.alive = 1 AND hu.hp >= 40 AND lo.sec <= coalesce(:until, 600) - 12
        AND (hu.x - lo.x) * (hu.x - lo.x) + (hu.y - lo.y) * (hu.y - lo.y) <= 1000 * 1000
),
ls AS (SELECT DISTINCT game_id, pid, team, pos, sec, x, y, hp FROM pr),
runs AS (
    SELECT ls.*, sum(CASE WHEN prev IS NULL OR sec - prev > 15 THEN 1 ELSE 0 END) OVER (PARTITION BY game_id, pid ORDER BY sec) AS k
    FROM (SELECT ls.*, lag(sec) OVER (PARTITION BY game_id, pid ORDER BY sec) AS prev FROM ls) ls
),
ch AS MATERIALIZED (
    SELECT game_id, pid, team, pos, sec AS t, x, y, hp FROM (
        SELECT runs.*, row_number() OVER (PARTITION BY game_id, pid, k ORDER BY sec) AS rn FROM runs
    ) WHERE rn = 1
),
atk AS MATERIALIZED (
    SELECT ch.game_id, ch.pid, ch.t, a.pid AS apid, a.mode
    FROM ch JOIN hs a ON a.game_id = ch.game_id AND a.team <> ch.team AND a.sec BETWEEN ch.t AND ch.t + 8
    WHERE a.tid = 'h' || ch.pid
),
-- Each hunter's modes over [t, t + 8], for its commonest one.
hm AS (
    SELECT p.game_id, p.pid, p.sec AS t, p.hpid, h.mode, count(*) AS n
    FROM pr p JOIN ch ON ch.game_id = p.game_id AND ch.pid = p.pid AND ch.t = p.sec
    JOIN hs h ON h.game_id = p.game_id AND h.pid = p.hpid AND h.sec BETWEEN p.sec AND p.sec + 8 AND h.mode IS NOT NULL
    GROUP BY p.game_id, p.pid, p.sec, p.hpid, h.mode
),
hmode AS (
    SELECT game_id, pid, t, hpid, mode FROM (
        SELECT hm.*, row_number() OVER (PARTITION BY game_id, pid, t, hpid ORDER BY n DESC, mode) AS rn FROM hm
    ) WHERE rn = 1
)
SELECT gm.file, ch.game_id, ch.team, ch.pid, ch.pos, ch.hp, ch.t, ch.x, ch.y,
    (SELECT count(DISTINCT apid) FROM atk WHERE atk.game_id = ch.game_id AND atk.pid = ch.pid AND atk.t = ch.t) AS attackers,
    EXISTS (SELECT 1 FROM cd WHERE cd.game_id = ch.game_id AND cd.pid = ch.pid AND cd.t >= ch.t AND cd.t <= ch.t + 12) AS died,
    (SELECT count(*) FROM pr p2 WHERE p2.game_id = ch.game_id AND p2.pid = ch.pid AND p2.sec = ch.t) AS nh,
    p.hpid, p.hpos, p.hhp, p.dist,
    EXISTS (SELECT 1 FROM atk WHERE atk.game_id = ch.game_id AND atk.pid = ch.pid AND atk.t = ch.t AND atk.apid = p.hpid) AS hatk,
    hmode.mode AS hmode
FROM ch JOIN gm ON gm.game_id = ch.game_id
JOIN pr p ON p.game_id = ch.game_id AND p.pid = ch.pid AND p.sec = ch.t
LEFT JOIN hmode ON hmode.game_id = ch.game_id AND hmode.pid = ch.pid AND hmode.t = ch.t AND hmode.hpid = p.hpid
ORDER BY gm.file, ch.t, ch.pid, p.hpid
