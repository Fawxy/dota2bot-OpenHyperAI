-- Fragment (`-- include: hero_second`): one game's heroes and their per-second series, as dynamic.js `series` (part A of its
-- retirement, docs/team/slices/retire-dynamic-a.md). The including query opens with WITH RECURSIVE and defines `gm(game_id)`
-- first, as `SELECT +game_id AS game_id ...` so the ev_ game_id index is used (LOGGING.md). Ends with a comma. CTEs:
--   hs_bot(pid, team, hero)   heroes whose last ev=bot or ev=player line has a team and that logged a snapshot with x
--   hs_snap(pid, team, seq, t, x, y, alive, deaths, lh, kills, tp)   their snapshots with x (tp = the previous snapshot's t)
--   hs_last(last)             the last snapshot time of any of them (snapshots without x count here, as in `series`)
--   hs_end(e)                 `last` down to a whole minute (dynamicMetrics' `end`)
--   hs_sec(pid, team, s, seq, t, x, y, alive, lh, deaths)   per hero, per whole second from its first snapshot to `last`: the
--                             latest snapshot at or before s; alive = 0 in a death gap (dead_after), else the snapshot's alive
-- Death gap (`deadAfter`): bots log no snapshot while dead, so the gap after a snapshot is dead time when it is over 2.5 s and the
-- next snapshot's deaths counter is higher, or when it runs to `last` (dynamic.js `C.DEAD_GAP`).
-- ensure: ev_bot(pid, team, hero)
-- ensure: ev_player(pid, team, hero)
-- ensure: ev_snap(pid, x, y, alive, deaths, lh, kills)
hs_who AS (
    SELECT pid, team, hero, row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn
    FROM (
        SELECT pid, team, hero, seq FROM ev_bot WHERE game_id = (SELECT game_id FROM gm) AND pid IS NOT NULL
        UNION ALL
        SELECT pid, team, hero, seq FROM ev_player WHERE game_id = (SELECT game_id FROM gm) AND pid IS NOT NULL
    )
),
hs_bot AS MATERIALIZED (
    SELECT w.pid, w.team, w.hero FROM hs_who w
    WHERE w.rn = 1 AND w.team IS NOT NULL
      AND EXISTS (SELECT 1 FROM ev_snap s WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid = w.pid AND typeof(s.x) IN ('integer', 'real'))
),
hs_snap AS MATERIALIZED (
    SELECT s.pid, b.team, s.seq, s.t, s.x, s.y, s.alive, s.deaths, s.lh, s.kills,
        lag(s.t) OVER (PARTITION BY s.pid ORDER BY s.t, s.seq) AS tp
    FROM ev_snap s JOIN hs_bot b ON b.pid = s.pid
    WHERE s.game_id = (SELECT game_id FROM gm) AND typeof(s.x) IN ('integer', 'real')
),
hs_last AS MATERIALIZED (
    SELECT max(s.t) AS last FROM ev_snap s WHERE s.game_id = (SELECT game_id FROM gm) AND s.pid IN (SELECT pid FROM hs_bot)
),
hs_end AS MATERIALIZED (SELECT CAST(floor((SELECT last FROM hs_last) / 60) AS INTEGER) * 60 AS e),
hs_span AS (
    SELECT pid, team, seq, t, x, y, alive, lh, deaths,
        CASE WHEN tn IS NULL THEN (SELECT last FROM hs_last) - t > 2.5
             ELSE tn - t > 2.5 AND typeof(dn) IN ('integer', 'real') AND dn > coalesce(deaths, 0) END AS dead_after,
        CAST(ceil(t) AS INTEGER) AS s0,
        CASE WHEN tn IS NULL THEN CAST(floor((SELECT last FROM hs_last)) AS INTEGER) ELSE CAST(ceil(tn) AS INTEGER) - 1 END AS s1
    FROM (
        SELECT hs_snap.*, lead(t) OVER w AS tn, lead(deaths) OVER w AS dn
        FROM hs_snap WINDOW w AS (PARTITION BY pid ORDER BY t, seq)
    )
),
hs_run AS (
    SELECT pid, team, s0 AS s, s1, seq, t, x, y, alive, lh, deaths, dead_after FROM hs_span WHERE s0 <= s1
    UNION ALL
    SELECT pid, team, s + 1, s1, seq, t, x, y, alive, lh, deaths, dead_after FROM hs_run WHERE s + 1 <= s1
),
hs_sec AS MATERIALIZED (
    SELECT pid, team, s, seq, t, x, y, CASE WHEN dead_after AND s > t THEN 0 ELSE alive END AS alive, lh, deaths FROM hs_run
),
