-- Last-hit and deny attempts with the verb's message unpacked (slice lane-last-hits, L.1 calibration): one row per ev=lh of a
-- game whose file matches :like (default every game), :from <= t < :until (default 0-600). Pre-swing fields from `msg`: `w` seconds
-- waited, `why` what held the swing on the last frame (range|cd|hp50|wait|start; NULL once a swing fired), `sw` a retarget (1 another
-- creep, 0 dropped; NULL otherwise). Swing fields (NULL when no swing fired): `hp` creep HP at the order, `pred` believed HP at
-- landing before our hit, `mine` believed own damage, `thit` predicted seconds to landing, `m` frame margin used, `endhp` creep HP
-- at the result (0 gone), `dt` seconds from the order to the result; calibration fields from bot 31f0c0a on (NULL before): `fa` seconds
-- from the order until GetLastAttackTime rose (-1 never), `lhp` creep HP on the first frame at or past `thit` (0 gone, -1 not reached),
-- `fg` mean frame gap the verb saw; from the swing-model change on: `obs` the creep's observed damage rate (HP/s lower bound the
-- verb read from the creep's HP while waiting), `idps` the DPS of the attackers the index saw on it at the swing. `err` = pred - lhp
-- only where the creep was still alive at the predicted landing (lhp > 0: ours had not landed, so lhp is the real HP the prediction
-- was about): positive means the belief expected more incoming damage than landed. A gone creep (lhp = 0) says nothing about the
-- prediction when ours took it, so err is NULL there. Enemy hero wind-ups the swing counted as certain (slice lasthit-refine-logs;
-- NULL when none, or before it): `ew` how many, `er` 1 when the swing was due only because of them, `ec` the latest of their
-- commit points (s to their attack point) and `oc` ours (s from the order to our attack point); oc > ec means we commit after them. Enemy-hero watch over every frame the verb watched the creep, swung or not (slice lasthit-windup-logs; NULL before): `hf` frames with an enemy hero attacking it, `hwf` those the wind-up reader read as winding up (hf > 0 with hwf = 0 across many attempts: the reader fails on heroes), `ha` `hc` `hpt` that hero's raw GetAnimActivity, GetAnimCycle and GetAttackPoint (of the last wind-up frame once one was seen). Kill window (bug-hunt mark 27; NULL before): `wo` s to the first frame a swing ordered then would be due (exact belief until the skill error is first rolled, the rolled one after; -1 never), `wb` what held the swing on that first open frame, not the swing frame (swing|paused|range|cd|hp50|none), `wn` open frames, `wg` longest gap between the frames the verb was stepped over the whole attempt, confirm wait included (s; the pause signal, `wb=paused` marks only a pause on the first open frame). `swung` 1 when a swing fired. Read with GROUP BY kind, ranged, reason; or err by thit.
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
        CASE WHEN instr(msg, 'fg=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'fg=') + 3, instr(substr(msg || ' ', instr(msg, 'fg=') + 3), ' ') - 1) AS real) END AS fg,
        CASE WHEN instr(msg, 'obs=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'obs=') + 4, instr(substr(msg || ' ', instr(msg, 'obs=') + 4), ' ') - 1) AS real) END AS obs,
        CASE WHEN instr(msg, 'idps=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'idps=') + 5, instr(substr(msg || ' ', instr(msg, 'idps=') + 5), ' ') - 1) AS real) END AS idps,
        CASE WHEN instr(msg, 'ew=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'ew=') + 3, instr(substr(msg || ' ', instr(msg, 'ew=') + 3), ' ') - 1) AS integer) END AS ew,
        CASE WHEN instr(msg, 'er=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'er=') + 3, instr(substr(msg || ' ', instr(msg, 'er=') + 3), ' ') - 1) AS integer) END AS er,
        CASE WHEN instr(msg, 'ec=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'ec=') + 3, instr(substr(msg || ' ', instr(msg, 'ec=') + 3), ' ') - 1) AS real) END AS ec,
        CASE WHEN instr(msg, 'oc=') > 0 THEN cast(substr(msg || ' ', instr(msg, 'oc=') + 3, instr(substr(msg || ' ', instr(msg, 'oc=') + 3), ' ') - 1) AS real) END AS oc,
        CASE WHEN instr(msg, ' hf=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' hf=') + 4, instr(substr(msg || ' ', instr(msg, ' hf=') + 4), ' ') - 1) AS integer) END AS hf,
        CASE WHEN instr(msg, ' hwf=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' hwf=') + 5, instr(substr(msg || ' ', instr(msg, ' hwf=') + 5), ' ') - 1) AS integer) END AS hwf,
        CASE WHEN instr(msg, ' ha=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' ha=') + 4, instr(substr(msg || ' ', instr(msg, ' ha=') + 4), ' ') - 1) AS integer) END AS ha,
        CASE WHEN instr(msg, ' hc=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' hc=') + 4, instr(substr(msg || ' ', instr(msg, ' hc=') + 4), ' ') - 1) AS real) END AS hc,
        CASE WHEN instr(msg, ' wo=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' wo=') + 4, instr(substr(msg || ' ', instr(msg, ' wo=') + 4), ' ') - 1) AS real) END AS wo,
        CASE WHEN instr(msg, ' wb=') > 0 THEN substr(msg || ' ', instr(msg, ' wb=') + 4, instr(substr(msg || ' ', instr(msg, ' wb=') + 4), ' ') - 1) END AS wb,
        CASE WHEN instr(msg, ' wn=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' wn=') + 4, instr(substr(msg || ' ', instr(msg, ' wn=') + 4), ' ') - 1) AS integer) END AS wn,
        CASE WHEN instr(msg, ' wg=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' wg=') + 4, instr(substr(msg || ' ', instr(msg, ' wg=') + 4), ' ') - 1) AS real) END AS wg,
        CASE WHEN instr(msg, ' hpt=') > 0 THEN cast(substr(msg || ' ', instr(msg, ' hpt=') + 5, instr(substr(msg || ' ', instr(msg, ' hpt=') + 5), ' ') - 1) AS real) END AS hpt
    FROM raw r
)
SELECT game_id, t, pid, kind, result, reason, ranged, eta, contested, ol, od, ow, walk, dies,
    NOT held AND hp IS NOT NULL AS swung, w, why, sw, hp, pred, mine, thit, m, endhp, dt, fa, lhp, fg, obs, idps, ew, er, ec, oc, hf, hwf, ha, hc, hpt, wo, wb, wn, wg,
    CASE WHEN NOT held AND pred IS NOT NULL AND lhp IS NOT NULL AND lhp > 0 THEN pred - lhp END AS err
FROM f
ORDER BY game_id, t;
