-- A pull scored per wave (docs/proposals/2026-11-05-pull-effect.md s2; slice support-lane `reading`): one row per `ok`
-- ev=pull_job (`grp` ok_div when `diverted`, as view pull_attempts: dt >= 0.75, div where a line has no dt; else ok_undiv)
-- and one control row per lane slot that wanted a pull and got none (`grp` none: ev=choice kind=pull want=1 go=0 with no
-- ev=pull_job of either team on that lane within 20 s of the slot; one row per game, team, lane and slot).
-- The pulled wave (pull rows only; fragment pull_farm, as @pull_farm with its 45 s neutral window): n_puller, n_ours,
--   own_died, own_denied, them_took, them_core.
-- Their wave at our side: enemy lane creeps in the pulling team's creep_fate that died from the slot to slot + 75 s
--   (exclusive) within 2,500 of our front at the slot (fx, fy of the first ev=lane_read of that team and lane in the 5 s from
--   the slot; none, and every e_ and o_ column is null): e_dead all of them, e_core our pos 1-3's last hits, e_ours other heroes of ours, e_denied denied by an enemy
--   hero, e_tower no hero and tw=1 (our tower was hitting it the frame before; not necessarily the killing blow), e_none no hero and not the tower (creeps, spells, nobody);
--   e_tw every one of them with tw=1, whoever got it (the deaths under our tower).
--   o_dead, o_denied: our own lane creeps (creep_fate side own) in the same window and place, and our denies of them, less
--   on pull rows those within 800 of the pulled camp's spawn (the pulled wave, counted in own_died). Only
--   deaths within 1,500 of one of our heroes are logged (ev=creep_death), so a wave that died with none of us near is absent.
--   Windows of consecutive slots overlap (75 s against a 30 s wave cycle): read a group's means, not sums over slots.
-- The lane after the slot: eq0, eq30 (ev=lane_read eq, -1 our T1 .. +1 theirs, first reading in the 5 s from slot and slot + 30);
--   tw30 = 1 when eq30 < -0.8 (their wave under our tower by 30 s, EC-090).
-- The next meeting point: the first ev=lane_read of that team and lane 60-90 s after the slot while our nearest tower on the
--   lane is the T1 (tw = 1): eq60_90, meet_own = its distance from our T1 along the lane, (eq + 1) / 2 times the T1-T1 path
--   length (lane_push_data LANE_PATHS towers: top 4,321, mid 2,902, bot 4,517; eq is read in lane-amount space from the two
--   fronts, so this is the fronts' meet, not lane_push's forecast clash); target = lane_push TargetOf (900 side lanes,
--   1,300 mid); meet_d = meet_own - target (positive: beyond the target towards their tower); meet_tw = 1 when meet_own
--   <= 700 (our T1's attack range: the meet sits under our tower). Null when no such reading. eq spans our nearest tower to
--   theirs, so with their T1 down the proxy reads short (rare in the laning window).
-- needs: ev_pull_job(pid, lane, camp, slot, res, div, dt)
-- ensure: ev_choice(pid, kind, go, want, lane, slot)
-- ensure: ev_lane_read(team, lane, eq, fx, fy, tw)
-- ensure: ev_bot(pid, team, pos)
WITH
-- include: camp_spawns
gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games),
pfw(win) AS (SELECT 45),
-- include: pull_farm
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos FROM ev_bot WHERE team IS NOT NULL GROUP BY 1, 2),
slots AS MATERIALIZED (
    SELECT j.game_id, j.seq, j.pid, tm.team, j.lane, j.camp, j.slot,
        CASE WHEN coalesce(j.dt, j.div) >= 0.75 THEN 'ok_div' ELSE 'ok_undiv' END AS grp
    FROM ev_pull_job j JOIN tm ON tm.game_id = j.game_id AND tm.pid = j.pid
    WHERE j.res = 'ok'
    UNION ALL
    SELECT c.game_id, min(c.seq), min(c.pid), tm.team, c.lane, NULL, c.slot, 'none'
    FROM ev_choice c JOIN tm ON tm.game_id = c.game_id AND tm.pid = c.pid
    WHERE c.kind = 'pull' AND c.want = 1 AND c.go = 0
        AND NOT EXISTS (SELECT 1 FROM ev_pull_job j WHERE j.game_id = c.game_id AND j.lane = c.lane AND abs(j.slot - c.slot) < 20)
    GROUP BY c.game_id, tm.team, c.lane, c.slot
),
rd AS MATERIALIZED (
    SELECT s.*,
        (SELECT r.t FROM ev_lane_read r WHERE r.game_id = s.game_id AND r.t >= s.slot AND r.t < s.slot + 5 AND r.team = s.team AND r.lane = s.lane ORDER BY r.t LIMIT 1) AS t0,
        (SELECT r.eq FROM ev_lane_read r WHERE r.game_id = s.game_id AND r.t >= s.slot + 30 AND r.t < s.slot + 35 AND r.team = s.team AND r.lane = s.lane ORDER BY r.t LIMIT 1) AS eq30,
        (SELECT r.t FROM ev_lane_read r WHERE r.game_id = s.game_id AND r.t >= s.slot + 60 AND r.t < s.slot + 90 AND r.team = s.team AND r.lane = s.lane AND r.tw = 1 ORDER BY r.t LIMIT 1) AS t60
    FROM slots s
),
fr AS MATERIALIZED (
    SELECT d.*, r0.fx, r0.fy, r0.eq AS eq0, r6.eq AS eq60_90,
        CASE d.lane WHEN 2 THEN 2902 WHEN 1 THEN 4321 ELSE 4517 END AS span,
        CASE d.lane WHEN 2 THEN 1300 ELSE 900 END AS target
        , cp.x AS cx, cp.y AS cy
    FROM rd d
    LEFT JOIN camps cp ON cp.idx = d.camp
    LEFT JOIN ev_lane_read r0 ON r0.game_id = d.game_id AND r0.t = d.t0 AND r0.team = d.team AND r0.lane = d.lane
    LEFT JOIN ev_lane_read r6 ON r6.game_id = d.game_id AND r6.t = d.t60 AND r6.team = d.team AND r6.lane = d.lane
),
cf AS MATERIALIZED (SELECT game_id, team, side, t, x, y, fate, pid, tw FROM creep_fate),
fate AS (
    SELECT f.game_id, f.seq, f.team,
        sum(c.side = 'enemy') AS e_dead,
        sum(c.side = 'enemy' AND c.fate = 'own_lh' AND b.pos BETWEEN 1 AND 3) AS e_core,
        sum(c.side = 'enemy' AND c.fate = 'own_lh' AND coalesce(b.pos, 0) NOT BETWEEN 1 AND 3) AS e_ours,
        sum(c.side = 'enemy' AND c.fate = 'enemy_deny') AS e_denied,
        sum(c.side = 'enemy' AND c.fate = 'other' AND c.tw = 1) AS e_tower,
        sum(c.side = 'enemy' AND c.fate = 'other' AND coalesce(c.tw, 0) <> 1) AS e_none,
        sum(c.side = 'enemy' AND c.tw = 1) AS e_tw,
        sum(c.side = 'own') AS o_dead,
        sum(c.side = 'own' AND c.fate = 'own_deny') AS o_denied
    FROM fr f
    JOIN cf c ON c.game_id = f.game_id AND c.team = f.team AND c.t >= f.slot AND c.t < f.slot + 75
        AND (c.x - f.fx) * (c.x - f.fx) + (c.y - f.fy) * (c.y - f.fy) <= 2500 * 2500
        AND NOT (c.side = 'own' AND f.cx IS NOT NULL AND (c.x - f.cx) * (c.x - f.cx) + (c.y - f.cy) * (c.y - f.cy) <= 800 * 800)
    LEFT JOIN tm b ON b.game_id = c.game_id AND CAST(b.pid AS TEXT) = CAST(c.pid AS TEXT)
    WHERE f.fx IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT f.game_id, g.file, g.game, f.seq, f.team, f.pid, f.lane, f.camp, f.slot, f.grp,
    p.n_puller, p.n_ours, p.own_died, p.own_denied, p.them_took, p.them_core,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_dead, 0) END AS e_dead,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_core, 0) END AS e_core,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_ours, 0) END AS e_ours,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_denied, 0) END AS e_denied,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_tower, 0) END AS e_tower,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_none, 0) END AS e_none,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.e_tw, 0) END AS e_tw,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.o_dead, 0) END AS o_dead,
    CASE WHEN f.fx IS NULL THEN NULL ELSE coalesce(w.o_denied, 0) END AS o_denied,
    f.eq0, f.eq30, CASE WHEN f.eq30 IS NULL THEN NULL WHEN f.eq30 < -0.8 THEN 1 ELSE 0 END AS tw30,
    f.eq60_90, f.target,
    CASE WHEN f.eq60_90 IS NULL THEN NULL ELSE round((f.eq60_90 + 1) / 2.0 * f.span) END AS meet_own,
    CASE WHEN f.eq60_90 IS NULL THEN NULL ELSE round((f.eq60_90 + 1) / 2.0 * f.span) - f.target END AS meet_d,
    CASE WHEN f.eq60_90 IS NULL THEN NULL WHEN (f.eq60_90 + 1) / 2.0 * f.span <= 700 THEN 1 ELSE 0 END AS meet_tw
FROM fr f JOIN games g USING (game_id)
LEFT JOIN pf_rows p ON f.grp <> 'none' AND p.game_id = f.game_id AND p.seq = f.seq
LEFT JOIN fate w ON w.game_id = f.game_id AND w.seq = f.seq AND w.team = f.team
