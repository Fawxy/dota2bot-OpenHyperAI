-- One unit's life in one game, as one result set read by `part`: `life` (the unit_life row: columns of view unit_life, as `detail`), and in a game
-- `hlog.js replay` has read (rp_game rows) also `pos` (its path, one row a second: t x y hp) and `hit` (the hits it took and dealt: t, `dir` taken|dealt, `other`
-- the hero on the other side, dmg, inf the inflictor, empty for an attack). Params: like (a run label or log path fragment), uid (a unit_life uid: a replay
-- unit `<ent>.<n>`, a log unit `2:412`; `scene`'s footer names one), game (the game's number in its log, default the log's last). Reads only that game's
-- rows by game_id, as @unit_life. A unit in a game with no replay rows has the life part only: paths and hits are in no log.
-- unit_hit has no unit id (a damage entry names the kind, team and name of each side), so a hit is matched to the unit by those and by falling inside its
-- life (t0 to its death): `n_like` is how many units of that kind, team and name were alive then, and over 1 the hit may be a like unit's.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
WITH gm AS MATERIALIZED (
    SELECT +g.game_id AS game_id FROM games g
    WHERE g.file LIKE :like AND g.game = coalesce(:game, (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file))
),
ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death WHERE game_id IN (SELECT game_id FROM gm)),
ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen WHERE game_id IN (SELECT game_id FROM gm)),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone WHERE game_id IN (SELECT game_id FROM gm)),
ul_rp AS NOT MATERIALIZED (SELECT * FROM rp_unit WHERE game_id IN (SELECT game_id FROM gm)),
-- include: unit_life_rows
one AS MATERIALIZED (SELECT * FROM unit_life_rows WHERE uid = :uid),
ru AS MATERIALIZED (SELECT * FROM ul_rp WHERE uid = :uid),
lim AS (SELECT coalesce((SELECT until FROM rp_game WHERE game_id IN (SELECT game_id FROM gm)), 720) AS until),
hits AS MATERIALIZED (
    SELECT h.t, 'taken' AS dir, h.an AS other_name, h.ap AS other_pid, h.dmg, h.inf, h.ak AS ok, h.at AS ot
    FROM ru JOIN unit_hit h ON h.game_id = ru.game_id AND h.ak = 'hero' AND h.tk = ru.kind AND h.tt = ru.team AND h.tn = ru.name
        AND h.t >= ru.t0 AND h.t <= coalesce(ru.t1, (SELECT until FROM lim)) + coalesce(ru.kdt, 0) + 0.1
    UNION ALL
    SELECT h.t, 'dealt', h.tn, h.tp, h.dmg, h.inf, h.tk, h.tt
    FROM ru JOIN unit_hit h ON h.game_id = ru.game_id AND h.tk = 'hero' AND h.ak = ru.kind AND h.at = ru.team AND h.an = ru.name
        AND h.t >= ru.t0 AND h.t <= coalesce(ru.t1, (SELECT until FROM lim)) + coalesce(ru.kdt, 0) + 0.1
),
u AS (
SELECT 'life' AS part, t0 AS t, x0 AS x, y0 AS y, NULL AS hp, NULL AS dir, NULL AS other, NULL AS dmg, NULL AS inf, NULL AS n_like,
    'uid=' || uid || ' kind=' || kind || ' team=' || team || coalesce(' type=' || type, '') || coalesce(' lane=' || lane, '')
    || coalesce(' wave=' || wave, '') || coalesce(' camp=' || camp, '')
    || CASE WHEN t1 IS NULL THEN ' alive-or-unseen-dead' ELSE ' t1=' || t1 || ' at (' || x1 || ',' || y1 || ')' END
    || ' by=' || coalesce(by_kind, '-') || coalesce(':' || by_pid, '') || coalesce(' src=' || by_src, '') || ' from=' || src || coalesce(' hid=' || hid, '') AS detail, 0 AS ord
FROM one
UNION ALL
SELECT 'pos', p.t, p.x, p.y, p.hp, NULL, NULL, NULL, NULL, NULL, NULL, 1
FROM ru JOIN unit_pos p ON p.game_id = ru.game_id AND p.uid = ru.uid
UNION ALL
SELECT 'hit', h.t, NULL, NULL, NULL, h.dir,
    CASE WHEN h.ok = 'hero' THEN h.other_pid || ' ' || replace(h.other_name, 'npc_dota_hero_', '') ELSE h.other_name END, h.dmg, h.inf,
    (SELECT count(*) FROM rp_unit r WHERE r.game_id = ru.game_id AND r.kind = ru.kind AND r.team = ru.team AND r.name = ru.name
        AND r.t0 <= h.t AND (r.t1 IS NULL OR r.t1 >= h.t)), NULL, 2
FROM hits h, ru
)
SELECT part, t, x, y, hp, dir, other, dmg, inf, n_like, detail FROM u ORDER BY ord, t
