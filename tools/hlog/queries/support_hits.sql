-- A support's lane hits (slice support-lane-hits, L.2s and H.2): one row per lineup position 4-5 hero per game whose file matches
-- :like (default every game), before :until (s, default 600). lh, dn: its last-hit and deny counters at the last ev=snap before
-- until. From ev=lh (the laning body's attempts): lh_n / lh_ok last-hit attempts and those that landed, split by the claim that
-- gave the creep to the support (`busy`: its core in an attempt on another creep; `free`: no core near enough), dn_n / dn_ok
-- deny attempts. A build before the claims (deny-only body) logs no last-hit attempts, so lh there is OHA's.
-- ensure: ev_lh(pid, kind, result, claim)
-- ensure: ev_snap(pid, lh, dn)
-- ensure: ev_bot(pid, team, pos)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file, game FROM games WHERE file LIKE coalesce(:like, '%')),
sup AS (SELECT l.game_id, l.team, l.pos, l.pid FROM lineup l WHERE l.game_id IN (SELECT game_id FROM gm) AND l.pos IN (4, 5)),
att AS (
    SELECT e.game_id, e.pid,
        sum(e.kind = 'lasthit') AS lh_n, sum(e.kind = 'lasthit' AND e.result = 'ok') AS lh_ok,
        sum(e.kind = 'lasthit' AND e.claim = 'busy') AS busy_n, sum(e.kind = 'lasthit' AND e.claim = 'busy' AND e.result = 'ok') AS busy_ok,
        sum(e.kind = 'lasthit' AND e.claim = 'free') AS free_n, sum(e.kind = 'lasthit' AND e.claim = 'free' AND e.result = 'ok') AS free_ok,
        sum(e.kind = 'deny') AS dn_n, sum(e.kind = 'deny' AND e.result = 'ok') AS dn_ok
    FROM ev_lh e WHERE e.game_id IN (SELECT game_id FROM gm) AND e.t < coalesce(:until, 600)
    GROUP BY e.game_id, e.pid
)
SELECT gm.file, gm.game, s.team, s.pos, s.pid,
    (SELECT n.lh FROM ev_snap n WHERE n.game_id = s.game_id AND n.pid = s.pid AND n.t < coalesce(:until, 600) AND n.lh IS NOT NULL
        ORDER BY n.t DESC, n.seq DESC LIMIT 1) AS lh,
    (SELECT n.dn FROM ev_snap n WHERE n.game_id = s.game_id AND n.pid = s.pid AND n.t < coalesce(:until, 600) AND n.dn IS NOT NULL
        ORDER BY n.t DESC, n.seq DESC LIMIT 1) AS dn,
    coalesce(a.lh_n, 0) AS lh_n, coalesce(a.lh_ok, 0) AS lh_ok, coalesce(a.busy_n, 0) AS busy_n, coalesce(a.busy_ok, 0) AS busy_ok,
    coalesce(a.free_n, 0) AS free_n, coalesce(a.free_ok, 0) AS free_ok, coalesce(a.dn_n, 0) AS dn_n, coalesce(a.dn_ok, 0) AS dn_ok
FROM sup s JOIN gm ON gm.game_id = s.game_id LEFT JOIN att a ON a.game_id = s.game_id AND a.pid = s.pid
ORDER BY gm.file, gm.game, s.team, s.pos
