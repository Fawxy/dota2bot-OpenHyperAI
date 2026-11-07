-- Stack yields (slice lane-control 3): each support stack minute the stack gave to the lane's pull (ev=stack res=skip
-- why=lane), in games whose file matches :like, and what the pull did with it: started (an ev=pull_job of the same support
-- whose slot, the pulled spawn, falls in the 60 s after the skip: a pull that ran before the yield did not buy it, and one
-- bought may fall in the next minute, review M1), ok (that pull's res=ok), and when no pull started, the pull
-- choice's last refusal in that window (ev=choice kind=pull go=0, its why; `ctl` when the line has no why: the decision did
-- not want it). One row per refusal reason plus `all`: n yields, started share, ok share.
-- ensure: ev_stack(pid, min, res, why)
-- ensure: ev_pull_job(pid, slot, res)
-- ensure: ev_choice(pid, kind, go, slot)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
y AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t, s.min AS m FROM ev_stack s JOIN gm ON gm.game_id = s.game_id
    WHERE s.res = 'skip' AND s.why = 'lane'
),
f AS (
    SELECT y.*,
        (SELECT count(*) FROM ev_pull_job p WHERE p.game_id = y.game_id AND p.pid = y.pid
            AND p.slot >= y.t AND p.slot < y.t + 60) AS started,
        (SELECT count(*) FROM ev_pull_job p WHERE p.game_id = y.game_id AND p.pid = y.pid
            AND p.slot >= y.t AND p.slot < y.t + 60 AND p.res = 'ok') AS ok,
        (SELECT coalesce(c.why, 'ctl') FROM ev_choice c WHERE c.game_id = y.game_id AND c.pid = y.pid AND c.kind = 'pull'
            AND c.go = 0 AND c.slot >= y.t AND c.slot < y.t + 60 ORDER BY c.t DESC LIMIT 1) AS refused
    FROM y
)
SELECT why, count(*) AS n, round(1.0 * sum(started > 0) / count(*), 2) AS started,
    round(1.0 * sum(ok > 0) / count(*), 2) AS ok
FROM (SELECT CASE WHEN started > 0 THEN 'started' ELSE coalesce(refused, 'none') END AS why, started, ok FROM f
      UNION ALL SELECT 'all', started, ok FROM f)
GROUP BY why ORDER BY why = 'all', n DESC;
