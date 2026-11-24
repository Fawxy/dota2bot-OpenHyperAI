-- Fragment (`-- include: unit_life_lane`): the lane creeps' half of fragment unit_life_rows (read for its header: the rules and columns), alone, for a reader that wants no neutral and no
-- replay row (SQLite plans a long CTE chain slowly, so the timeline does not carry the neutral half). The includer defines `ul_gm(game_id)` and includes `unit_life_in` first. CTEs
-- `ul_new` .. `ul_lane` (fragment unit_life_seen is included here), `ul_odeath` and `creep_fate_rows` (below) and `ul_lall(game_id, uid, kind, team, type, lane, wave, camp, t0, x0, y0, t1, x1, y1, by_kind, by_pid, by_src, hid, cd_seq, cd_t, cd_x, cd_y, tw, seq, hp1, near)`: the lane rows of
-- unit_life_rows before its src column. Ends with a comma.
-- `ul_odeath(game_id, seq, t, team, kind, x, y, uid, by_kind, by_pid, by_src, hp1, cd_seq, dny)`: the owner's lines ev=own_creep_death was, one per lane creep that died within 1,500 of a living hero of its
-- team (`near`) at half health or less (`hp1`, NULL counts): `seq` its closing line, `t`, `x`, `y` its last sighting, `kind` melee, ranged or siege (a flag bearer is a melee creep),
-- `by_pid` the denier or the enemy hero who took it (by_kind says which; `by_src` own is not always set for a deny: an enemy line with `tw` makes it paired), `dny` the owner's denier (the old `by` of the owner's line: a pid, NULL for none; by_kind deny with a pid), `cd_seq` the other team's creep_death line it paired to (NULL: no enemy line took it, so it is a creep the taker did not log). A reader of the own side's deny chances (deny_reach, lane_aggro, idle_fate, the xp memo) reads this.
-- ensure: ev_wave_creep_death(team, kind, x, y, hp, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, hp, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, hp, by, tw, cid)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
-- ensure: ev_snap(pid, alive, x, y)
-- ensure: ev_bot(pid, team)
-- include: unit_life_seen
ul_c AS MATERIALIZED (
    SELECT game_id, seq, t, 5 - team AS owner, kind, x, y, CAST("by" AS TEXT) AS who, coalesce(tw, 0) AS tw, cid, hp
    FROM ul_enemy WHERE team IN (2, 3)
),
-- the own lines whose creep has a wave line (same team and cid) are that line's: the keys, for the anti-join below
ul_wk AS MATERIALIZED (SELECT DISTINCT game_id, team, cid FROM ul_wave WHERE cid IS NOT NULL),
ul_o AS MATERIALIZED (
    SELECT w.game_id, w.seq, w.t, w.team, w.kind, w.x, w.y, CAST(w."by" AS TEXT) AS who, w.cid, w.lane, w.born, NULL AS utype, NULL AS x0, NULL AS y0, w.hp
    FROM ul_wave w WHERE w.game_id NOT IN (SELECT game_id FROM ul_new)
    UNION ALL
    SELECT o.game_id, o.seq, o.t, o.team, o.kind, o.x, o.y, CAST(o."by" AS TEXT), o.cid, NULL, NULL, NULL, NULL, NULL, o.hp
    FROM ul_own o
    WHERE o.game_id NOT IN (SELECT game_id FROM ul_new)
        AND NOT EXISTS (SELECT 1 FROM ul_wk w WHERE w.game_id = o.game_id AND w.team = o.team AND w.cid = o.cid)
    UNION ALL
    -- a game with unit_seen: every own lane creep, from its first sighting (born = its t to 0.1 s, as wave_creep_death's born is; alive at the end: no t, x, y, who), its kind as the
    -- old events name it (a flag bearer is a melee creep there, so the enemy's creep_death pairs by it) and its own type beside
    SELECT s.game_id, coalesce(g.seq, s.seq), g.t, s.team,
        CASE WHEN s.type LIKE '%siege%' THEN 'siege' WHEN s.type LIKE '%ranged%' THEN 'ranged' ELSE 'melee' END,
        g.x, g.y, g.who, s.cid, s.lane, round(s.t, 1),
        CASE WHEN s.type LIKE '%flagbearer%' THEN 'flag' END, s.x, s.y, g.hp
    FROM ul_s s LEFT JOIN ul_g g ON g.game_id = s.game_id AND g.team = s.team AND g.cid = s.cid
    WHERE s.kind = 'lane'
),
ul_pair AS MATERIALIZED (
    SELECT game_id, oseq, sseq FROM (
        SELECT game_id, oseq, sseq,
            row_number() OVER (PARTITION BY game_id, oseq ORDER BY d2, dt, sseq) AS ro,
            row_number() OVER (PARTITION BY game_id, sseq ORDER BY d2, dt, oseq) AS rs
        FROM (
            SELECT u.game_id, u.seq AS oseq, s.seq AS sseq, abs(s.t - u.t) AS dt,
                (s.x - u.x) * (s.x - u.x) + (s.y - u.y) * (s.y - u.y) AS d2
            FROM ul_o u JOIN ul_c s ON s.game_id = u.game_id AND s.owner = u.team AND s.kind = u.kind
                AND s.t BETWEEN u.t - 1 AND u.t + 1 AND (s.x - u.x) * (s.x - u.x) + (s.y - u.y) * (s.y - u.y) <= 62500
        )
    ) WHERE ro = 1 AND rs = 1
),
-- A creep that leaves the taker's sight at low health is logged as a death (ev=creep_revive may follow), so one cid can have
-- several lines: an unpaired sighting is a unit only as its cid's last line, and not when another line of that cid paired.
ul_cpair AS MATERIALIZED (
    SELECT DISTINCT s.game_id, s.owner, s.cid FROM ul_pair p JOIN ul_c s ON s.game_id = p.game_id AND s.seq = p.sseq WHERE s.cid IS NOT NULL
),
ul_clast AS MATERIALIZED (
    SELECT game_id, owner, cid, max(seq) AS lastseq FROM ul_c WHERE cid IS NOT NULL GROUP BY game_id, owner, cid
),
ul_lane AS MATERIALIZED (
    SELECT u.game_id, u.team || ':' || coalesce(u.cid, 'e' || u.seq) AS uid, u.team, coalesce(u.utype, u.kind) AS type, u.lane, u.born,
        u.t, u.x, u.y, u.who AS owho, s.who AS swho, s.tw, s.seq IS NOT NULL AS paired, u.x0, u.y0,
        u.seq AS oseq, s.seq AS cd_seq, s.t AS cd_t, s.x AS cd_x, s.y AS cd_y, u.hp AS hp1
    FROM ul_o u
    LEFT JOIN ul_pair p ON p.game_id = u.game_id AND p.oseq = u.seq
    LEFT JOIN ul_c s ON s.game_id = p.game_id AND s.seq = p.sseq
    UNION ALL
    SELECT s.game_id, s.owner || ':' || 'x' || coalesce(s.cid, 'e' || s.seq), s.owner, s.kind, NULL, NULL,
        s.t, s.x, s.y, NULL, s.who, s.tw, 0, NULL, NULL,
        NULL, s.seq, s.t, s.x, s.y, s.hp
    FROM ul_c s
    WHERE s.game_id NOT IN (SELECT game_id FROM ul_new)
        AND NOT EXISTS (SELECT 1 FROM ul_pair p WHERE p.game_id = s.game_id AND p.sseq = s.seq)
        AND (s.cid IS NULL OR (s.seq = (SELECT c.lastseq FROM ul_clast c WHERE c.game_id = s.game_id AND c.owner = s.owner AND c.cid = s.cid)
            AND NOT EXISTS (SELECT 1 FROM ul_cpair c WHERE c.game_id = s.game_id AND c.owner = s.owner AND c.cid = s.cid)))
),
ul_lall AS MATERIALIZED (
    SELECT l.game_id, l.uid, 'lane' AS kind, l.team, l.type, l.lane, CAST(l.born / 30 AS INTEGER) AS wave,
        NULL AS camp, l.born AS t0, l.x0, l.y0, l.t AS t1, l.x AS x1, l.y AS y1,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') THEN 'hero'
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' OR l.swho = 'deny' THEN 'deny'
             WHEN l.tw = 1 THEN 'tower' ELSE 'unknown' END AS by_kind,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') THEN l.swho
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' THEN l.owho END AS by_pid,
        CASE WHEN l.swho IS NOT NULL AND l.swho NOT IN ('none', 'deny') OR l.swho = 'deny' OR l.tw = 1 THEN CASE WHEN l.paired THEN 'paired' ELSE 'taker' END
             WHEN l.owho IS NOT NULL AND l.owho <> 'none' THEN 'own' END AS by_src,
        NULL AS hid, l.cd_seq, l.cd_t, l.cd_x, l.cd_y, l.tw, l.oseq AS seq, l.hp1,
        CASE WHEN l.t IS NOT NULL THEN EXISTS (
            SELECT 1 FROM ev_bot b JOIN ev_snap h ON h.game_id = b.game_id AND h.pid = b.pid AND h.t >= l.t - 1.0 AND h.t <= l.t
            WHERE b.game_id = l.game_id AND b.team = l.team AND h.alive <> 0
                AND (h.x - l.x) * (h.x - l.x) + (h.y - l.y) * (h.y - l.y) <= 2250000) END AS near
    FROM ul_lane l
),
ul_odeath AS (
    SELECT u.game_id, u.seq, u.t1 AS t, u.team, CASE WHEN u.type = 'flag' THEN 'melee' ELSE u.type END AS kind, u.x1 AS x, u.y1 AS y, u.uid, u.by_kind,
        CAST(u.by_pid AS INTEGER) AS by_pid, u.by_src, u.hp1, u.cd_seq, CASE WHEN u.by_kind = 'deny' THEN CAST(u.by_pid AS INTEGER) END AS dny
    FROM ul_lall u WHERE u.seq IS NOT NULL AND u.t1 IS NOT NULL AND u.near = 1 AND (u.hp1 IS NULL OR u.hp1 <= 0.5)
),
-- creep_fate_rows(game_id, seq, t, team, side, kind, x, y, fate, pid, tw): view creep_fate's rows (its header has the rule), one per lane creep death from the lane rows
-- above. A creep death has up to two: the taker's (`enemy`: the creep_death line it paired to, so `seq` is that line's) and the owner's (`own`: the closing line, kept
-- as a deny chance: the creep died within 1,500 of a living hero of its owner's team (`near`) at half health or less (`hp1`, NULL counts)). A creep a hero took
-- is in both; which of the two to count is the reader's.
creep_fate_rows AS (
    SELECT u.game_id, u.cd_seq AS seq, u.cd_t AS t, 5 - u.team AS team, 'enemy' AS side, CASE WHEN u.type = 'flag' THEN 'melee' ELSE u.type END AS kind,
        u.cd_x AS x, u.cd_y AS y,
        CASE u.by_kind WHEN 'hero' THEN 'own_lh' WHEN 'deny' THEN 'enemy_deny' ELSE 'other' END AS fate,
        CASE WHEN u.by_kind IN ('hero', 'deny') THEN CAST(u.by_pid AS INTEGER) END AS pid, u.tw
    FROM ul_lall u WHERE u.cd_seq IS NOT NULL
    UNION ALL
    SELECT u.game_id, u.seq, u.t, u.team, 'own', u.kind, u.x, u.y,
        CASE WHEN u.by_kind = 'deny' THEN 'own_deny' ELSE 'lost' END,
        CASE WHEN u.by_kind = 'deny' THEN CAST(u.by_pid AS INTEGER) END, NULL
    FROM ul_odeath u
),
