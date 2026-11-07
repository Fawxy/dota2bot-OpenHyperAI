-- Pull drills (bot humaniser/drill.ts `pull`, `core-pull`; master slices/lane-controller.md "Drills"): one row per pull slot
-- the drill decided, in games whose file matches :like. `input` on (ev=choice kind=pull rule=drill) or off (why=drill, the
-- control); `go` and `why` the pull's start (a refused input-on rep names its own gate); `res` and `why_end` the pull job's
-- result for that slot (NULL when it never started); `div` its diverted share. Joined to the lane controller's decision
-- for the pulled wave (the wave whose 30 s holds the slot, as @lane_ctl) and its check 45 s on: `m45` the plain forecast,
-- `pe` the predicted pull effect, `own45` the clash at the check, `effect` own45 - m45 (what the lane did against the plain
-- forecast; on input-on reps the pull's observed effect, on control reps the forecast's own error), `e_plain` |m45 - own45|,
-- `e_ctl` |m45 + pe - own45| on input-on reps that pulled ok (else e_plain).
-- ensure: ev_choice(pid, kind, go, why, rule, lane, slot)
-- ensure: ev_pull_job(pid, slot, res, why, div)
-- ensure: ev_lane_ctl(team, lane, kind, wave, own, m45, pe)
-- ensure: ev_drill(ph, name, pid, team)
WITH
gm AS MATERIALIZED (
    SELECT DISTINCT d.game_id FROM ev_drill d JOIN games g ON g.game_id = d.game_id
    WHERE d.ph = 'role' AND d.name IN ('pull', 'core-pull') AND g.file LIKE coalesce(:like, '%')
),
tm AS MATERIALIZED (
    SELECT d.game_id, d.pid, max(d.team) AS team FROM ev_drill d JOIN gm USING (game_id) WHERE d.ph = 'role' GROUP BY 1, 2
),
ch AS MATERIALIZED (
    SELECT c.game_id, c.pid, tm.team, c.lane, c.slot, c.go, c.why,
        CASE WHEN c.rule = 'drill' THEN 'on' ELSE 'off' END AS input,
        CAST(c.slot / 30 AS INTEGER) * 30 AS wave
    FROM ev_choice c JOIN gm USING (game_id) JOIN tm ON tm.game_id = c.game_id AND tm.pid = c.pid
    WHERE c.kind = 'pull' AND (c.rule = 'drill' OR c.why = 'drill')
),
r AS (
    SELECT ch.*,
        (SELECT p.res FROM ev_pull_job p WHERE p.game_id = ch.game_id AND p.pid = ch.pid AND abs(p.slot - ch.slot) < 2 ORDER BY p.t LIMIT 1) AS res,
        (SELECT p.why FROM ev_pull_job p WHERE p.game_id = ch.game_id AND p.pid = ch.pid AND abs(p.slot - ch.slot) < 2 ORDER BY p.t LIMIT 1) AS why_end,
        (SELECT p.div FROM ev_pull_job p WHERE p.game_id = ch.game_id AND p.pid = ch.pid AND abs(p.slot - ch.slot) < 2 ORDER BY p.t LIMIT 1) AS div,
        d.m45, d.pe, k.own AS own45
    FROM ch
    LEFT JOIN ev_lane_ctl d ON d.game_id = ch.game_id AND d.team = ch.team AND d.lane = ch.lane AND d.kind = 'wave' AND d.wave = ch.wave
    LEFT JOIN ev_lane_ctl k ON k.game_id = ch.game_id AND k.team = ch.team AND k.lane = ch.lane AND k.kind = 'chk' AND k.wave = ch.wave
)
SELECT game_id, pid, team, lane, wave, round(slot, 1) AS slot, input, go, why, res, why_end, div, m45, pe, own45,
    own45 - m45 AS effect, abs(m45 - own45) AS e_plain,
    CASE WHEN input = 'on' AND res = 'ok' AND pe IS NOT NULL THEN abs(m45 + pe - own45) ELSE abs(m45 - own45) END AS e_ctl
FROM r
ORDER BY game_id, slot;
