-- The idle swing (slice idle-swing, states/idle_swing; lane controller design s5.6) in games whose file matches :like.
-- One row per kind (predeny, shove): `swings` ev=idle_swing lines, `ok` those whose attack fired, `creeps` the creeps a bot
-- started on (its ok swing with n = 0; two laners on one creep count twice, once per laner), and for predeny the creep's fate:
-- the logging team's own creep death (view creep_fate, side own) of the same kind (ranged or not) first in time within
-- 8 s after the bot's last ok swing on it and within 500 of that swing's creep place: `denied` (fate own_deny, any of
-- our heroes; `by_me` this bot), `lost` (fate lost: an enemy last hit, a tower or creep kill), `unmatched` (no death found:
-- alive past the window or a death the 50% rule did not log). `rate` = denied / creeps, the per-attempt target's measure.
-- `self` swings whose own attack took the deny (dn), `focus` creeps started with an ally already on it, `fail` swings that did
-- not fire.
-- ensure: ev_idle_swing(pid, kind, n, cx, cy, ranged, result, dn, focus)
-- ensure: ev_bot(pid, team)
WITH
gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
tm AS MATERIALIZED (SELECT game_id, pid, max(team) AS team FROM ev_bot WHERE game_id IN (SELECT game_id FROM gm) GROUP BY 1, 2),
s AS MATERIALIZED (
    SELECT i.game_id, i.seq, i.t, i.pid, tm.team, i.kind, i.n, i.cx, i.cy, coalesce(i.ranged, 0) AS ranged, i.result,
        coalesce(i.dn, 0) AS dn, coalesce(i.focus, 0) AS focus
    FROM ev_idle_swing i JOIN tm ON tm.game_id = i.game_id AND tm.pid = i.pid
    WHERE i.game_id IN (SELECT game_id FROM gm)
),
-- Each ok predeny swing belongs to the creep its bot last started (n = 0); creep k of a bot is the k-th start.
ok AS (
    SELECT s.*, sum(CASE WHEN n = 0 THEN 1 ELSE 0 END) OVER (PARTITION BY game_id, pid ORDER BY t, seq) AS k
    FROM s WHERE kind = 'predeny' AND result = 'ok'
),
cr AS (
    SELECT game_id, pid, team, k, max(ranged) AS ranged, max(focus * (n = 0)) AS focus,
        max(t) AS t1, (SELECT o2.cx FROM ok o2 WHERE o2.game_id = ok.game_id AND o2.pid = ok.pid AND o2.k = ok.k ORDER BY o2.t DESC LIMIT 1) AS x,
        (SELECT o2.cy FROM ok o2 WHERE o2.game_id = ok.game_id AND o2.pid = ok.pid AND o2.k = ok.k ORDER BY o2.t DESC LIMIT 1) AS y
    FROM ok WHERE k > 0 GROUP BY game_id, pid, team, k
),
fate AS (
    SELECT cr.*, (
        SELECT c.fate || ':' || coalesce(CAST(c.pid AS TEXT), '')
        FROM creep_fate c
        WHERE c.game_id = cr.game_id AND c.side = 'own' AND c.team = cr.team
            AND (c.kind LIKE '%ranged%' OR c.kind LIKE '%siege%') = (cr.ranged = 1)
            AND c.t >= cr.t1 AND c.t <= cr.t1 + 8
            AND (c.x - cr.x) * (c.x - cr.x) + (c.y - cr.y) * (c.y - cr.y) <= 500 * 500
        ORDER BY c.t LIMIT 1
    ) AS f
    FROM cr
)
SELECT 'predeny' AS kind,
    (SELECT count(*) FROM s WHERE kind = 'predeny') AS swings,
    (SELECT count(*) FROM s WHERE kind = 'predeny' AND result = 'ok') AS ok,
    (SELECT count(*) FROM s WHERE kind = 'predeny' AND result <> 'ok') AS fail,
    count(*) AS creeps,
    sum(f LIKE 'own_deny:%') AS denied,
    sum(f = 'own_deny:' || CAST(pid AS TEXT)) AS by_me,
    sum(f LIKE 'lost:%') AS lost,
    sum(f IS NULL) AS unmatched,
    round(1.0 * sum(f LIKE 'own_deny:%') / max(count(*), 1), 2) AS rate,
    (SELECT count(*) FROM s WHERE kind = 'predeny' AND dn = 1) AS self,
    sum(focus) AS focus
FROM fate
UNION ALL
SELECT 'shove', count(*), sum(result = 'ok'), sum(result <> 'ok'), NULL, NULL, NULL, NULL, NULL, NULL, sum(dn), NULL
FROM s WHERE kind = 'shove';
