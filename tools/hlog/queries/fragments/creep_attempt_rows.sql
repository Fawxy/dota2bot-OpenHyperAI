-- Fragment (`-- include: creep_attempt_rows`): the creep row's attempts (creep_row.ts, `ev=job job=creep`), one row each, joined to
-- the creep's death and the hero's deaths; one definition for @creep_attempts and @creep_attempt_rows. The includer defines
-- `gm(game_id)` first. CTE `creep_attempt_rows(game_id, pid, team, pos, hero, t0, t1, len, cid, gw, rng, melee, why, cut, arr, tin, wt, pw, pq, ps, hc,
-- sw, hp0, hp1, hplost, dt, gap, swon, cls, died, msg, paid, mpos, walkin, fate, gn, sp, hw, hm, hs, sa, nw, ontime)`:
--   cid, gw    the start line's (logs from oha-creep-early); before them, the creep row's `go=1` choice line whose slot + gat is
--              within 0.35 s of the start (its cid and gw)
--   rng        the start line's attack range, else the creep death's for the hero's position, else the nearest snapshot's `ar`;
--              melee is rng under 300
--   wt         the end line's seconds from the go to the row's first step (-1 never stepped; NULL on logs before oha-creep-swing)
--   pw, pq, ps seconds the attempt spent in the verb's phases, walk (outside reach), wait (in reach, no swing ordered) and swing (ordered, to
--              the end); hc seconds from the go to the hold turning hard (0 with the phase rule `go`, -1 never); all NULL on logs
--              before oha-creep-swing's commit C
--   arr        on a cut: `after` when the hero had been in the verb's range (tin >= 0 and at or before the end), `before` when
--              not, NULL on logs without tin
--   hp0, hp1   the end line's, else the hero's snapshot `hv` at or before the start and the end (a snapshot a second: rough)
--   dt, gap,   the creep's death (the hero's team's `creep_death` of that cid from the start to 5 s past the end, the nearest the
--   swon       end): its t, the hero's distance less its range then, and 1 when the hero was attacking it then (`p<pos>t`)
--   cls        landed (why ok), cut (why preempted), lost_swing (a swing on the creep as it died), lost_inrange (within the
--              engine's attack reach at its death, no swing on it: the start line's `rch`, attack range and both hulls; range + 48 on
--              logs before it), lost_out (farther), lost_nodeath (no death joined)
--   died       1 when the hero died from the start to 5 s past the end (fragment ep_death)
--   paid       who was paid for the creep, from the unit-life pairing (fragment unit_life_lane, so any time in the game) of the creep's
--              death line found for dt, by its line, not a time window: `self` (this hero last-hit it), `mate` (another hero of its
--              team did; `mpos` that hero's position), `deny` (an enemy hero denied it), `tower` (the taker's log has one of its
--              towers on it and no hero), `other` (a creep, a spell nobody logged, or a death its owner saw only); NULL when no death
--              line was joined. `self` is the pid of the line's `by`, so a deny never reads `self`
--   walkin     1 when the start's walk at go (`gw`) is over 0, 0 when it is 0, NULL when unknown
--   gn, sp     the start line's need at go (s to order a swing from inside the verb's range) and the spare at go (gd less gn);
--              hw, hm what held the row for the creep while it was about to come due (last refusal; the hero's mode when it was
--              `held`; NULL when it went at the first such read), hs seconds from that first read to the go, sa 1 when the hero's
--              attack target was the creep at the go, nw 1 when the go came at the first read that listed the creep; all NULL on
--              logs before oha-creep-ontime
--   ontime     1 when sp >= 0, 0 when under, NULL when sp is unknown
--   fate       one class from paid and why: self_row (self, why ok), self_other (self, the row did not end ok), mate, deny, tower,
--              unpaid (paid other), nodeath (no death joined)
-- Ends with a comma.
-- ensure: ev_job(pid, job, phase, why, cut, cid, gw, gd, rng, rch, tin, wt, pw, pq, ps, hc, sw, hp0, hp1, msg, gn, sp, hw, hm, hs, sa, nw)
-- ensure: ev_choice(pid, kind, go, slot, gat, gw, cid)
-- ensure: ev_creep_death(team, cid, p1d, p1r, p1t, p2d, p2r, p2t, p3d, p3r, p3t)
-- ensure: ev_snap(pid, hv, ar)
-- ensure: ev_bot(pid, team, pos, hero)
-- include: ep_death
ul_gm AS (SELECT game_id FROM gm),
-- include: unit_life_in
-- include: unit_life_lane
ca_bot AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos, max(hero) AS hero FROM ev_bot
    WHERE game_id IN (SELECT game_id FROM gm) GROUP BY game_id, pid),
ca_e AS MATERIALIZED (
    SELECT game_id, seq, t, pid, phase, why, cut, cid, gw, rng, rch, gn, sp, hw, hm, hs, sa, nw, tin, wt, pw, pq, ps, hc, sw, hp0, hp1, msg,
        lead(phase) OVER w AS nphase, lead(t) OVER w AS nt, lead(why) OVER w AS nwhy, lead(cut) OVER w AS ncut, lead(cid) OVER w AS ncid,
        lead(tin) OVER w AS ntin, lead(wt) OVER w AS nwt, lead(pw) OVER w AS npw, lead(pq) OVER w AS npq, lead(ps) OVER w AS nps, lead(hc) OVER w AS nhc, lead(sw) OVER w AS nsw, lead(hp0) OVER w AS nhp0, lead(hp1) OVER w AS nhp1, lead(msg) OVER w AS nmsg
    FROM ev_job WHERE game_id IN (SELECT game_id FROM gm) AND job = 'creep' AND phase IN ('start', 'end')
    WINDOW w AS (PARTITION BY game_id, pid ORDER BY seq)
),
ca_s AS MATERIALIZED (
    SELECT s.game_id, s.pid, s.t AS t0, s.nt AS t1, s.nwhy AS why, s.ncut AS cut, coalesce(s.cid, s.ncid) AS jcid, s.gw AS jgw, s.rng AS jrng, s.rch AS jrch, s.gn, s.sp, s.hw, s.hm, s.hs, s.sa, s.nw,
        s.ntin AS tin, s.nwt AS wt, s.npw AS pw, s.npq AS pq, s.nps AS ps, s.nhc AS hc, s.nsw AS sw, s.nhp0 AS hp0, s.nhp1 AS hp1, s.nmsg AS msg
    FROM ca_e s WHERE s.phase = 'start' AND s.nphase = 'end'
),
ca_c AS MATERIALIZED (
    SELECT a.game_id, a.pid, a.t0, c.cid, c.gw,
        row_number() OVER (PARTITION BY a.game_id, a.pid, a.t0 ORDER BY abs(c.slot + c.gat - a.t0)) AS r
    FROM ca_s a JOIN ev_choice c ON c.game_id = a.game_id AND c.pid = a.pid AND c.kind = 'creep' AND c.go = 1
        AND abs(c.slot + c.gat - a.t0) < 0.35
),
ca_g AS MATERIALIZED (
    SELECT a.*, b.team, b.pos, b.hero, coalesce(a.jcid, c.cid) AS cid, coalesce(a.jgw, c.gw) AS gw
    FROM ca_s a JOIN ca_bot b ON b.game_id = a.game_id AND b.pid = a.pid
    LEFT JOIN ca_c c ON c.game_id = a.game_id AND c.pid = a.pid AND c.t0 = a.t0 AND c.r = 1
),
ca_d AS MATERIALIZED (
    SELECT g.game_id, g.pid, g.t0, d.t AS dt, d.seq AS dseq,
        CASE g.pos WHEN 1 THEN d.p1d WHEN 2 THEN d.p2d WHEN 3 THEN d.p3d END AS dd,
        CASE g.pos WHEN 1 THEN d.p1r WHEN 2 THEN d.p2r WHEN 3 THEN d.p3r END AS dr,
        CASE g.pos WHEN 1 THEN d.p1t WHEN 2 THEN d.p2t WHEN 3 THEN d.p3t END AS dtg,
        row_number() OVER (PARTITION BY g.game_id, g.pid, g.t0 ORDER BY abs(d.t - g.t1)) AS r
    FROM ca_g g JOIN ev_creep_death d ON d.game_id = g.game_id AND d.team = g.team AND d.cid = g.cid
        AND d.t >= g.t0 AND d.t <= g.t1 + 5
),
ca_x AS MATERIALIZED (
    SELECT g.*, d.dt, d.dseq, d.dd, d.dr, d.dtg,
        coalesce(g.hp0, (SELECT s.hv FROM ev_snap s WHERE s.game_id = g.game_id AND s.pid = g.pid AND s.t <= g.t0 ORDER BY s.t DESC LIMIT 1)) AS xhp0,
        coalesce(g.hp1, (SELECT s.hv FROM ev_snap s WHERE s.game_id = g.game_id AND s.pid = g.pid AND s.t <= g.t1 ORDER BY s.t DESC LIMIT 1)) AS xhp1,
        coalesce(g.jrng, d.dr, (SELECT s.ar FROM ev_snap s WHERE s.game_id = g.game_id AND s.pid = g.pid AND s.t <= g.t0 ORDER BY s.t DESC LIMIT 1)) AS xrng
    FROM ca_g g LEFT JOIN ca_d d ON d.game_id = g.game_id AND d.pid = g.pid AND d.t0 = g.t0 AND d.r = 1
),
ca_p AS MATERIALIZED (
    SELECT game_id, cd_seq, by_kind, CAST(by_pid AS INTEGER) AS by_pid FROM ul_lall WHERE cd_seq IS NOT NULL
),
ca_q AS MATERIALIZED (
    SELECT x.*, CASE WHEN p.cd_seq IS NULL THEN NULL
            WHEN p.by_kind = 'hero' THEN CASE WHEN p.by_pid = x.pid THEN 'self' ELSE 'mate' END
            WHEN p.by_kind = 'deny' THEN 'deny' WHEN p.by_kind = 'tower' THEN 'tower' ELSE 'other' END AS paid,
        CASE WHEN p.by_kind = 'hero' AND p.by_pid <> x.pid THEN (SELECT b.pos FROM ca_bot b WHERE b.game_id = x.game_id AND b.pid = p.by_pid) END AS mpos
    FROM ca_x x LEFT JOIN ca_p p ON p.game_id = x.game_id AND p.cd_seq = x.dseq
),
creep_attempt_rows AS (
    SELECT x.game_id, x.pid, x.team, x.pos, x.hero, x.t0, x.t1, round(x.t1 - x.t0, 2) AS len, x.cid, x.gw, x.xrng AS rng,
        x.xrng < 300 AS melee, x.why, x.cut,
        CASE WHEN x.why <> 'preempted' OR x.tin IS NULL THEN NULL WHEN x.tin >= 0 AND x.tin <= x.t1 - x.t0 THEN 'after' ELSE 'before' END AS arr,
        x.tin, x.wt, x.pw, x.pq, x.ps, x.hc, x.sw, x.xhp0 AS hp0, x.xhp1 AS hp1, x.xhp0 - x.xhp1 AS hplost, x.dt,
        CASE WHEN x.dd IS NOT NULL THEN x.dd - x.dr END AS gap, x.dtg AS swon,
        CASE WHEN x.why = 'ok' THEN 'landed' WHEN x.why = 'preempted' THEN 'cut' WHEN x.dt IS NULL OR x.dd IS NULL THEN 'lost_nodeath'
            WHEN x.dtg = 1 THEN 'lost_swing' WHEN x.dd <= coalesce(x.jrch, x.dr + 48) THEN 'lost_inrange' ELSE 'lost_out' END AS cls,
        EXISTS (SELECT 1 FROM ep_death e WHERE e.game_id = x.game_id AND e.pid = x.pid AND e.t >= x.t0 AND e.t <= x.t1 + 5) AS died,
        x.msg, x.paid, x.mpos, x.gn, x.sp, x.hw, x.hm, x.hs, x.sa, x.nw,
        CASE WHEN x.sp IS NULL THEN NULL WHEN x.sp >= 0 THEN 1 ELSE 0 END AS ontime, CASE WHEN x.gw IS NULL THEN NULL WHEN x.gw > 0 THEN 1 ELSE 0 END AS walkin,
        CASE WHEN x.paid IS NULL THEN 'nodeath' WHEN x.paid = 'self' THEN CASE WHEN x.why = 'ok' THEN 'self_row' ELSE 'self_other' END
            WHEN x.paid = 'other' THEN 'unpaid' ELSE x.paid END AS fate
    FROM ca_q x
),
