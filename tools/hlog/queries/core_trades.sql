-- Core in lane, trading (slice core-in-lane, L.2c): one row per game and lineup core (pos 1-3) to :until (default 600).
-- From ev=trade (states/core_trade): taken (result done or kill), kills, won (a taken trade where the target lost more HP than the
-- core), lost (a window attack mode never took, held by anything but a due last hit or retreat: the coverage number), yielded
-- (windows a due last hit, laning at desire 0.85 or more, or retreat held: intended priority), hpd and thpd summed over taken trades, aggroed (taken trades
-- with an enemy lane creep on the core at any point, `ag` > 0; NULL-safe on builds before the field). From lane_activity
-- (90 s to :until, as @lane_time): hero, seconds attacking a hero; trade_open and trade_open_hero as @lane_time; deaths at :until.
-- Params: like (LIKE pattern on games.file, default every game), until (seconds, default 600), pmin and pmax the lineup
-- positions (default 1-3; 4-5 reads Support in lane's harass, ev=trade role=support, slice support-spot).
-- ensure: ev_trade(pid, kind, result, why, dur, hpd, thpd, ag, mode, md)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
tr AS (
    SELECT tr.game_id, tr.pid,
        sum(tr.result IN ('done', 'kill')) AS taken, sum(tr.result = 'kill') AS kills,
        sum(tr.result IN ('done', 'kill') AND tr.thpd > tr.hpd) AS won, sum(tr.result = 'lost' AND NOT ((tr.mode = 1 AND tr.md >= 0.85) OR tr.mode = 4)) AS lost,
        sum(tr.result = 'lost' AND ((tr.mode = 1 AND tr.md >= 0.85) OR tr.mode = 4)) AS yielded,
        sum(CASE WHEN tr.result IN ('done', 'kill') THEN tr.hpd ELSE 0 END) AS hpd,
        sum(CASE WHEN tr.result IN ('done', 'kill') THEN tr.thpd ELSE 0 END) AS thpd,
        sum(tr.result IN ('done', 'kill') AND tr.ag > 0) AS aggroed
    FROM ev_trade tr JOIN gm ON gm.game_id = tr.game_id
    WHERE tr.t < coalesce(:until, 600)
    GROUP BY tr.game_id, tr.pid
),
la AS (
    SELECT a.game_id, a.pid, a.team, a.pos,
        sum(a.activity = 'hero') AS hero,
        sum(a.in_range AND a.ol = 0) AS trade_open, sum(a.in_range AND a.ol = 0 AND a.activity = 'hero') AS trade_open_hero,
        max(a.deaths) AS deaths
    FROM lane_activity a JOIN gm ON gm.game_id = a.game_id
    WHERE a.pos >= coalesce(:pmin, 1) AND a.pos <= coalesce(:pmax, 3) AND a.t >= 90 AND a.t < coalesce(:until, 600)
    GROUP BY a.game_id, a.pid, a.team, a.pos
)
SELECT gm.file, la.team, la.pos, la.pid, coalesce(tr.taken, 0) AS taken, coalesce(tr.kills, 0) AS kills, coalesce(tr.won, 0) AS won,
    coalesce(tr.lost, 0) AS lost, coalesce(tr.yielded, 0) AS yielded, coalesce(tr.hpd, 0) AS hpd, coalesce(tr.thpd, 0) AS thpd, coalesce(tr.aggroed, 0) AS aggroed,
    la.hero, la.trade_open, la.trade_open_hero, la.deaths
FROM la JOIN gm ON gm.game_id = la.game_id LEFT JOIN tr ON tr.game_id = la.game_id AND tr.pid = la.pid
ORDER BY gm.file, la.team, la.pos
