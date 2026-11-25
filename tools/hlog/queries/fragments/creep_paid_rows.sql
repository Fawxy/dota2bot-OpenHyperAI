-- Fragment (`-- include: creep_paid_rows`): the lane creeps family's line (master docs/proposals/2026-11-25-no-creep-unpaid.md s3),
-- one definition for @creep_paid and @creep_paid_games. The includer defines `gm(game_id)` first. CTE `creep_paid_rows(game_id, uid,
-- t, team, whose, kind, lane, how, paid, by_pid, tw, x, y, pid, pos, hln, dist, ar, gap, band, hp, atk, ed, busy, cpid, cgap, cband,
-- exact, cexact)`.
-- Params: from (default 0), until (default 600), deaths with from <= t < until. Ends with a comma.
--   unit    a lane creep death from unit_life's lane rows (fragment unit_life_lane), read twice: once for each team (`team`). `whose`
--           `theirs` (the other team's creep, one `team` could last-hit) or `ours` (`team`'s own, one it could deny). `t`, `x`, `y`
--           the death as `team`'s own log saw it (the taker's creep_death for theirs, the owner's closing line for ours), else the
--           other log's. `kind` melee, ranged or siege (a flag bearer is melee); `lane` the death place's (fragment lane_label).
--   how     `lh` an enemy hero of the creep's last hit (`by_pid`), `deny` its owner's hero denied it (`by_pid` when logged), `tower`
--           the taker's log has one of the taker's towers hitting it the frame before and no hero (under it, not surely killed by
--           it), `other` none of these: a creep, a spell nobody logged, or a death seen by its owner only. In an unrecorded game a
--           creep kill reads `other` (LOGGING.md, what a game can say about its units).
--   paid    `us` when a hero of `team` last-hit it, `them` when a hero of the other team did, `nobody` otherwise (a deny pays no
--           gold). Read as `team`'s: every death is in both teams' rows, paid `us` in one and `them` in the other. `tw` 1 when
--           the taker's log has one of the taker's towers hitting it the frame before, whoever took it; 0 none; NULL with no
--           taker line or on a build before the field.
--   reach   `team`'s nearest live hero at `t` within 1,500 (`pid`, `pos`, `hln` its snap's nearest lane). A hero is logged once a
--           second, so its distance has two sources. Measured (`exact` 1): a pos 1-3 hero on a creep of `theirs`, from the taker's
--           creep_death line, which logs each of its cores' distance and attack range on the frame of the death (`p1d`, `p1r`, ..:
--           cores within 1,500). Estimated (`exact` 0): any other hero, any creep of `ours`, and a line without the fields; its
--           place taken between its last snapshot at or before `t` and its first after (each within 1.5 s; one alone when the
--           other is missing or dead), so not the whole-second place. Against the measured distance the estimate is about 23
--           units off on average and reads a hero in range about one time in ten too seldom (a hero walks in, hits and walks
--           out between two samples); the whole-second place is about 140 off. `cexact` the same for `cpid`.
--           `dist` centre to centre; `ar` its attack range; `gap` = dist - (ar + 48), the 48 the telemetry's RANGE_SLACK (snap
--           `ce` uses it). `band` `in` (gap <= 0), `r150`, `r300` (gap to 150, 300), `r1500` (no
--           nearer band, dist <= 1,500), `none` (no live hero of `team` within 1,500; then every reach column is NULL), NULL for a
--           hero with no `ar` (older logs). `hp` its HP percent, `atk` 1 when it had an attack target (snap `tid` or `tgt`), `ed`
--           the nearest visible enemy hero within 1,200 (snap `ed`), all from the snapshot at or before `t` (the one after if
--           none). `busy` 1 when that hero last-hit or denied another lane creep within 1.2 s of `t`.
--           `cpid`, `cgap`, `cband` the same for `team`'s nearest live pos 1-3 hero (NULL when none within 1,500).
-- ensure: ev_snap(pid, x, y, alive, ar, hp, tid, tgt, ed, ln)
-- ensure: ev_bot(pid, team, pos, hero)
-- ensure: ev_creep_death(team, p1d, p1r, p2d, p2r, p3d, p3r)
ul_gm AS (SELECT game_id FROM gm),
-- include: unit_life_in
-- include: unit_life_lane
-- `ukey` names one death: in a log before unit_seen a uid can name creeps of several lanes.
cp_u AS MATERIALIZED (
    SELECT row_number() OVER () AS ukey, game_id, uid, team AS owner, CASE WHEN type = 'flag' THEN 'melee' ELSE type END AS kind, by_kind,
        CAST(by_pid AS INTEGER) AS by_pid, tw, t1, x1, y1, cd_seq, cd_t, cd_x, cd_y
    FROM ul_lall WHERE coalesce(t1, cd_t) IS NOT NULL
),
cp_v AS MATERIALIZED (
    SELECT row_number() OVER () AS rid, u.ukey, u.game_id, u.uid, v.team, CASE WHEN v.team = u.owner THEN 'ours' ELSE 'theirs' END AS whose,
        u.kind, u.by_kind, u.by_pid, u.tw,
        CASE WHEN v.team = u.owner THEN coalesce(u.t1, u.cd_t) ELSE coalesce(u.cd_t, u.t1) END AS t,
        CASE WHEN v.team = u.owner THEN CASE WHEN u.t1 IS NOT NULL THEN u.x1 ELSE u.cd_x END ELSE CASE WHEN u.cd_t IS NOT NULL THEN u.cd_x ELSE u.x1 END END AS x,
        CASE WHEN v.team = u.owner THEN CASE WHEN u.t1 IS NOT NULL THEN u.y1 ELSE u.cd_y END ELSE CASE WHEN u.cd_t IS NOT NULL THEN u.cd_y ELSE u.y1 END END AS y,
        CASE WHEN u.by_kind = 'hero' THEN 5 - u.owner END AS payee,
        c.p1d, c.p1r, c.p2d, c.p2r, c.p3d, c.p3r
    FROM cp_u u CROSS JOIN (SELECT 2 AS team UNION ALL SELECT 3) v
    -- the taker's own line (ev_creep_death is indexed by game and t): its cores' distances, for the taker's rows only
    LEFT JOIN ev_creep_death c ON v.team <> u.owner AND c.game_id = u.game_id AND c.t = u.cd_t AND c.seq = u.cd_seq
    WHERE CASE WHEN v.team = u.owner THEN coalesce(u.t1, u.cd_t) ELSE coalesce(u.cd_t, u.t1) END >= coalesce(:from, 0)
        AND CASE WHEN v.team = u.owner THEN coalesce(u.t1, u.cd_t) ELSE coalesce(u.cd_t, u.t1) END < coalesce(:until, 600)
),
cp_pts AS (SELECT game_id AS kind, rid AS k, rid AS seq, t, x, y FROM cp_v),
-- include: lane_label pts=cp_pts lab=cp_lab
cp_hb AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos, max(hero) AS hero FROM ev_bot
    WHERE game_id IN (SELECT game_id FROM gm) GROUP BY game_id, pid),
cp_hs AS MATERIALIZED (
    SELECT v.rid, v.game_id, v.t, v.x, v.y, h.pid, h.pos,
        CASE h.pos WHEN 1 THEN v.p1d WHEN 2 THEN v.p2d WHEN 3 THEN v.p3d END AS xd,
        CASE h.pos WHEN 1 THEN v.p1r WHEN 2 THEN v.p2r WHEN 3 THEN v.p3r END AS xr,
        (SELECT s.t FROM ev_snap s WHERE s.game_id = v.game_id AND s.pid = h.pid AND s.t <= v.t AND s.t >= v.t - 1.5
            ORDER BY s.t DESC LIMIT 1) AS sb,
        (SELECT s.t FROM ev_snap s WHERE s.game_id = v.game_id AND s.pid = h.pid AND s.t > v.t AND s.t <= v.t + 1.5
            ORDER BY s.t LIMIT 1) AS sa
    FROM cp_v v JOIN cp_hb h ON h.game_id = v.game_id AND h.team = v.team
),
cp_hp AS MATERIALIZED (
    SELECT q.*, coalesce(q.xd, sqrt((q.hx - q.x) * (q.hx - q.x) + (q.hy - q.y) * (q.hy - q.y))) AS dist, q.xd IS NOT NULL AS exact FROM (
        SELECT p.rid, p.game_id, p.t, p.x, p.y, p.pid, p.pos, p.xd,
            CASE WHEN b.seq IS NOT NULL AND a.seq IS NOT NULL THEN b.x + (a.x - b.x) * (p.t - b.t) / (a.t - b.t) ELSE coalesce(b.x, a.x) END AS hx,
            CASE WHEN b.seq IS NOT NULL AND a.seq IS NOT NULL THEN b.y + (a.y - b.y) * (p.t - b.t) / (a.t - b.t) ELSE coalesce(b.y, a.y) END AS hy,
            coalesce(p.xr, b.ar, a.ar) AS ar, coalesce(b.hp, a.hp) AS hp, coalesce(b.ln, a.ln) AS hln,
            CASE WHEN coalesce(b.seq, a.seq) IS NULL THEN NULL
                 WHEN coalesce(b.tid, b.tgt, CASE WHEN b.seq IS NULL THEN coalesce(a.tid, a.tgt) END) IS NOT NULL THEN 1 ELSE 0 END AS atk,
            CASE WHEN b.seq IS NOT NULL THEN b.ed ELSE a.ed END AS ed
        FROM cp_hs p
        LEFT JOIN ev_snap b ON b.game_id = p.game_id AND b.pid = p.pid AND b.t = p.sb AND b.alive = 1
        LEFT JOIN ev_snap a ON a.game_id = p.game_id AND a.pid = p.pid AND a.t = p.sa AND a.alive = 1
    ) q WHERE q.hx IS NOT NULL
),
cp_hr AS MATERIALIZED (
    SELECT h.*, h.dist - (h.ar + 48) AS gap,
        row_number() OVER (PARTITION BY h.game_id, h.rid ORDER BY h.dist, h.pid) AS rk,
        row_number() OVER (PARTITION BY h.game_id, h.rid ORDER BY h.pos BETWEEN 1 AND 3 DESC, h.dist, h.pid) AS crk
    FROM cp_hp h WHERE h.dist <= 1500
),
-- A hero's own lane creep takes, for `busy` (any lane creep, either side, within 1.2 s).
cp_took AS MATERIALIZED (SELECT game_id, ukey, by_pid, coalesce(cd_t, t1) AS t FROM cp_u WHERE by_kind IN ('hero', 'deny') AND by_pid IS NOT NULL),
creep_paid_rows AS (
    SELECT v.game_id, v.uid, v.t, v.team, v.whose, v.kind, coalesce(l.lane, 'other') AS lane,
        CASE v.by_kind WHEN 'hero' THEN 'lh' WHEN 'deny' THEN 'deny' WHEN 'tower' THEN 'tower' ELSE 'other' END AS how,
        CASE WHEN v.payee = v.team THEN 'us' WHEN v.payee IS NOT NULL THEN 'them' ELSE 'nobody' END AS paid,
        v.by_pid, v.tw, v.x, v.y, n.pid, n.pos, n.hln, round(n.dist) AS dist, n.ar, round(n.gap) AS gap,
        CASE WHEN n.pid IS NULL THEN 'none' WHEN n.ar IS NULL THEN NULL WHEN n.gap <= 0 THEN 'in' WHEN n.gap <= 150 THEN 'r150'
             WHEN n.gap <= 300 THEN 'r300' ELSE 'r1500' END AS band,
        n.hp, n.atk, n.ed,
        CASE WHEN n.pid IS NULL THEN NULL ELSE EXISTS (SELECT 1 FROM cp_took k WHERE k.game_id = v.game_id AND k.by_pid = n.pid
            AND k.ukey <> v.ukey AND k.t BETWEEN v.t - 1.2 AND v.t + 1.2) END AS busy,
        c.pid AS cpid, round(c.gap) AS cgap,
        CASE WHEN c.pid IS NULL THEN NULL WHEN c.ar IS NULL THEN NULL WHEN c.gap <= 0 THEN 'in' WHEN c.gap <= 150 THEN 'r150'
             WHEN c.gap <= 300 THEN 'r300' ELSE 'r1500' END AS cband,
        n.exact, c.exact AS cexact
    FROM cp_v v
    LEFT JOIN cp_lab l ON l.kind = v.game_id AND l.k = v.rid
    LEFT JOIN cp_hr n ON n.game_id = v.game_id AND n.rid = v.rid AND n.rk = 1
    LEFT JOIN cp_hr c ON c.game_id = v.game_id AND c.rid = v.rid AND c.crk = 1 AND c.pos BETWEEN 1 AND 3
),
