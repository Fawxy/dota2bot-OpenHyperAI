-- Last-hit and deny attempts with the verb's message unpacked (slice lane-last-hits, L.1 calibration): one row per ev=lh of a
-- game whose file matches :like (default every game), :from <= t < :until (default 0-600). Pre-swing fields from `msg`: `w` seconds
-- waited, `why` what held the swing on the last frame (range|cd|hp50|wait|start; NULL once a swing fired), `sw` a retarget (1 another
-- creep, 0 dropped; NULL otherwise). Swing fields (NULL when no swing fired): `hp` creep HP at the order, `pred` believed HP at
-- landing before our hit, `mine` believed own damage, `thit` predicted seconds to landing, `m` frame margin used, `endhp` creep HP
-- at the result (0 gone), `dt` seconds from the order to the result; calibration fields from bot 31f0c0a on (NULL before): `fa` seconds
-- from the order until GetLastAttackTime rose (-1 never), `lhp` creep HP on the first frame at or past `thit` (0 gone, -1 not reached),
-- `fg` mean frame gap the verb saw. `err` = pred - lhp where both are known and lhp >= 0: positive means the prediction expected more
-- incoming damage than landed (an early swing). `swung` 1 when a swing fired. Read with GROUP BY kind, ranged, reason; or err by thit.
-- ensure: ev_lh(pid, kind, result, reason, ranged, eta, contested, ol, od, ow, walk, dies, msg)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
raw AS (
    SELECT l.game_id, l.t, l.pid, l.kind, l.result, l.reason, l.ranged, l.eta, l.contested, l.ol, l.od, l.ow, l.walk, l.dies,
        coalesce(l.msg, '') AS msg
    FROM ev_lh l
    WHERE l.game_id IN (SELECT game_id FROM gm) AND l.t >= coalesce(:from, 0) AND l.t < coalesce(:until, 600)
),
-- One field: the number after `<key>=` up to the next space (or the end); NULL when the key is absent.
f AS (
    SELECT r.*,
        instr(msg, 'why=') > 0 AS held,
        CASE WHEN instr(msg, 'w=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'w=') + 2, instr(substr(msg || ' ', instr(msg, 'w=') + 2), ' ') - 1) AS real) END AS w,
        CASE WHEN instr(msg, 'why=') > 0 THEN substr(msg || ' ', instr(msg, 'why=') + 4, instr(substr(msg || ' ', instr(msg, 'why=') + 4), ' ') - 1) END AS why,
        CASE WHEN instr(msg, 'sw=') > 0 THEN cast(substr(msg, instr(msg, 'sw=') + 3, 1) AS integer) END AS sw,
        CASE WHEN instr(msg, ' hp=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' hp=') + 4, instr(substr(msg || ' ', instr(msg, ' hp=') + 4), ' ') - 1) AS real) END AS hp,
        CASE WHEN instr(msg, 'pred=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'pred=') + 5, instr(substr(msg || ' ', instr(msg, 'pred=') + 5), ' ') - 1) AS real) END AS pred,
        CASE WHEN instr(msg, 'mine=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'mine=') + 5, instr(substr(msg || ' ', instr(msg, 'mine=') + 5), ' ') - 1) AS real) END AS mine,
        CASE WHEN instr(msg, ' t=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' t=') + 3, instr(substr(msg || ' ', instr(msg, ' t=') + 3), ' ') - 1) AS real) END AS thit,
        CASE WHEN instr(msg, ' m=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' m=') + 3, instr(substr(msg || ' ', instr(msg, ' m=') + 3), ' ') - 1) AS real) END AS m,
        CASE WHEN instr(msg, 'end=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'end=') + 4, instr(substr(msg || ' ', instr(msg, 'end=') + 4), ' ') - 1) AS real) END AS endhp,
        CASE WHEN instr(msg, 'dt=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'dt=') + 3, instr(substr(msg || ' ', instr(msg, 'dt=') + 3), ' ') - 1) AS real) END AS dt,
        CASE WHEN instr(msg, 'fa=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'fa=') + 3, instr(substr(msg || ' ', instr(msg, 'fa=') + 3), ' ') - 1) AS real) END AS fa,
        CASE WHEN instr(msg, 'lhp=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'lhp=') + 4, instr(substr(msg || ' ', instr(msg, 'lhp=') + 4), ' ') - 1) AS real) END AS lhp,
        CASE WHEN instr(msg, 'fg=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'fg=') + 3, instr(substr(msg || ' ', instr(msg, 'fg=') + 3), ' ') - 1) AS real) END AS fg
    FROM raw r
)
SELECT game_id, t, pid, kind, result, reason, ranged, eta, contested, ol, od, ow, walk, dies,
    NOT held AND hp IS NOT NULL AS swung, w, why, sw, hp, pred, mine, thit, m, endhp, dt, fa, lhp, fg,
    CASE WHEN NOT held AND pred IS NOT NULL AND lhp IS NOT NULL AND lhp >= 0 THEN pred - lhp END AS err
FROM f
ORDER BY game_id, t;
