-- The chase after a loss of sight (slice chase-log, kill-chances step 3a; bot states/core_trade): one row per ev=chase
-- ph=lost (a CoreTrade episode whose target left sight), with what its watch logged next for the same hero: `seen` (the target
-- visible again), `dead`, `gone` (neither within 12 s) or `next` (a new loss replaced it); NULL when the game ended first.
--   side, pos   ours or oha (ev=bot `ours`), the chaser's lineup position
--   ek, tgt     the episode's kind and target; thp the target's HP share when last seen, hp ours, kh the kill bar
--   d, gap      our distance to the last sighting, and that past our attack range and both hulls
--   ms, tms     our move speed and the target's last read; hv, hd its heading over its last seen 0.5 to 1 s
--   nsp, sp     our ready damage spells: how many, and the records (name,cast range,cast point,behaviour,damage)
--   end_ph, end_dt, end_d, end_thp, end_on   the watch's end, seconds after the loss, our distance and its HP share when
--               seen, and the kind of our episode on it then
-- Params: like, until (default 720).
-- ensure: ev_chase(pid, ph, role, ek, tgt, dur, hp, thp, kh, d, gap, ms, tms, hv, hd, sp, dt, alive, mode, onk)
-- ensure: ev_bot(pid, team, pos, ours)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
who AS MATERIALIZED (
    SELECT game_id, pid, team, pos, CASE WHEN instr(coalesce(ours, ''), ':1') > 0 THEN 'ours' ELSE 'oha' END AS side
    FROM (
        SELECT b.game_id, b.pid, b.team, b.pos, b.ours, row_number() OVER (PARTITION BY b.game_id, b.pid ORDER BY b.seq DESC) AS rn
        FROM ev_bot b JOIN gm ON gm.game_id = b.game_id WHERE b.team IS NOT NULL AND b.pos IS NOT NULL
    ) WHERE rn = 1
),
ch AS MATERIALIZED (
    SELECT c.*, lead(c.ph) OVER w AS nph, lead(c.dt) OVER w AS ndt, lead(c.d) OVER w AS nd, lead(c.thp) OVER w AS nthp,
        lead(c.onk) OVER w AS non
    FROM ev_chase c JOIN gm ON gm.game_id = c.game_id
    WINDOW w AS (PARTITION BY c.game_id, c.pid ORDER BY c.seq)
)
SELECT gm.file, ch.game_id, ch.t, ch.pid, w.side, w.pos, ch.role, ch.ek, ch.tgt, ch.dur, ch.hp, ch.thp, ch.kh, ch.d, ch.gap,
    ch.ms, ch.tms, ch.hv, ch.hd,
    CASE WHEN ch.sp IS NULL OR ch.sp = '' THEN 0 ELSE length(ch.sp) - length(replace(ch.sp, ';', '')) + 1 END AS nsp, ch.sp,
    CASE WHEN ch.nph = 'lost' THEN NULL ELSE ch.nph END AS end_ph,
    CASE WHEN ch.nph = 'lost' THEN NULL ELSE ch.ndt END AS end_dt,
    CASE WHEN ch.nph = 'seen' THEN ch.nd END AS end_d,
    CASE WHEN ch.nph = 'seen' THEN ch.nthp END AS end_thp,
    CASE WHEN ch.nph = 'lost' THEN NULL ELSE ch.non END AS end_on
FROM ch JOIN gm ON gm.game_id = ch.game_id LEFT JOIN who w ON w.game_id = ch.game_id AND w.pid = ch.pid
WHERE ch.ph = 'lost' AND ch.t <= coalesce(:until, 720)
ORDER BY ch.game_id, ch.t, ch.pid
