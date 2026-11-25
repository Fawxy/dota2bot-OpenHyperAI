-- Fragment (`-- include: creep_offer_rows`): the lane creep offer's lines joined to their creep's death, one definition for @creep_offers,
-- @creep_offer_cells and @creep_offer_grades (read @creep_offers's header for the join and the params). The includer defines `gm(game_id)`
-- first. CTE `creep_offer_rows(game_id, seq, t, team, pos, hero, pid, lane, slot, want, cid, ck, who, wo, wl, walk, due, dies, slk, hpp, mode,
-- crhp, g2, g2r, pc, pd, ptw, eh, exs, en, kb, kt, md, ed, ein, atk, matched, src, dt, how, paid, by_pid, mine, inrange, outdmg, covered, snap)`.
-- Params: from, until, back, fwd, ck, who, pid, hero. Ends with a comma.
-- ensure: ev_choice(pid, kind, src, lane, slot, want, cid, ck, who, wo, wl, walk, due, dies, slk, hpp, mode, crhp, g2, g2r, pc, pd, ptw, eh, exs, en, kb, kt, md, ed, ein, atk)
-- ensure: ev_snap(pid, x, y, alive)
-- ensure: ev_bot(pid, team, pos, hero)
-- include: creep_paid_rows
co_bot AS MATERIALIZED (SELECT game_id, pid, max(team) AS team, max(pos) AS pos, max(hero) AS hero FROM ev_bot
    WHERE game_id IN (SELECT game_id FROM gm) GROUP BY game_id, pid),
co_l AS MATERIALIZED (
    SELECT c.game_id, c.seq, c.t, b.team, b.pos, b.hero, c.pid, c.lane, c.slot, c.want, c.cid, c.ck, c.who,
        CASE c.who WHEN 't' THEN 'theirs' ELSE 'ours' END AS whose,
        c.wo, c.wl, c.walk, c.due, c.dies, c.slk, c.hpp, c.mode, c.crhp, c.g2, c.g2r, c.pc, c.pd, c.ptw, c.eh, c.exs, c.en,
        c.kb, c.kt, c.md, c.ed, c.ein, c.atk
    FROM ev_choice c JOIN co_bot b ON b.game_id = c.game_id AND b.pid = c.pid
    WHERE c.kind = 'creep' AND c.src = 'shadow' AND c.game_id IN (SELECT game_id FROM gm)
        AND c.t >= coalesce(:from, 0) AND c.t < coalesce(:until, 600)
        AND (:ck IS NULL OR instr(',' || :ck || ',', ',' || c.ck || ',') > 0)
        AND (:who IS NULL OR instr(',' || :who || ',', ',' || c.who || ',') > 0)
        AND (:pid IS NULL OR instr(',' || :pid || ',', ',' || c.pid || ',') > 0)
        AND (:hero IS NULL OR instr(',' || :hero || ',', ',' || b.hero || ',') > 0)
),
co_c AS MATERIALIZED (
    SELECT game_id, seq, uid, dt, how, paid, by_pid, x, y FROM (
        SELECT l.game_id, l.seq, p.uid, p.t AS dt, p.how, p.paid, p.by_pid, p.x, p.y,
            row_number() OVER (PARTITION BY l.game_id, l.seq ORDER BY abs(p.t - l.t), p.uid) AS r
        FROM co_l l JOIN creep_paid_rows p ON p.game_id = l.game_id AND p.team = l.team AND p.lcid = l.cid AND p.whose = l.whose
            AND p.t >= l.t - coalesce(:back, 1) AND p.t <= l.t + coalesce(:fwd, 1)
    ) WHERE r = 1
),
co_o AS MATERIALIZED (
    SELECT l.game_id, l.seq, p.uid, p.t AS dt, p.how, p.paid, p.by_pid, p.x, p.y,
        abs(p.t - l.t) AS gap,
        (SELECT s.x FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.t <= l.t AND s.alive = 1 ORDER BY s.t DESC LIMIT 1) AS hx,
        (SELECT s.y FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid AND s.t <= l.t AND s.alive = 1 ORDER BY s.t DESC LIMIT 1) AS hy
    FROM co_l l JOIN creep_paid_rows p ON p.game_id = l.game_id AND p.team = l.team AND p.whose = 'theirs' AND p.lcid IS NULL
        AND p.kind = CASE l.ck WHEN 'm' THEN 'melee' WHEN 'f' THEN 'melee' WHEN 'r' THEN 'ranged' ELSE 'siege' END
        AND p.t >= l.t - coalesce(:back, 1) AND p.t <= l.t + coalesce(:fwd, 1)
    WHERE l.who = 't' AND NOT EXISTS (SELECT 1 FROM co_c c WHERE c.game_id = l.game_id AND c.seq = l.seq)
),
co_w AS MATERIALIZED (
    SELECT * FROM co_o WHERE hx IS NOT NULL AND (x - hx) * (x - hx) + (y - hy) * (y - hy) <= 2250000
),
-- a death is the owner-side match of a line only when it is the one candidate for that line and no line of another creep has it as a candidate
co_f AS MATERIALIZED (
    SELECT w.* FROM co_w w
    WHERE (SELECT count(*) FROM co_w v WHERE v.game_id = w.game_id AND v.seq = w.seq) = 1
        AND (SELECT count(DISTINCT v.seq) FROM co_w v JOIN co_l a ON a.game_id = v.game_id AND a.seq = v.seq JOIN co_l b ON b.game_id = w.game_id AND b.seq = w.seq WHERE v.game_id = w.game_id AND v.uid = w.uid AND a.cid <> b.cid) = 0
        AND NOT EXISTS (SELECT 1 FROM co_c c WHERE c.game_id = w.game_id AND c.uid = w.uid)
),
creep_offer_rows AS (
    SELECT l.game_id, l.seq, l.t, l.team, l.pos, l.hero, l.pid, l.lane, l.slot, l.want, l.cid, l.ck, l.who,
        l.wo, l.wl, l.walk, l.due, l.dies, l.slk, l.hpp, l.mode, l.crhp, l.g2, l.g2r, l.pc, l.pd, l.ptw, l.eh, l.exs, l.en,
        l.kb, l.kt, l.md, l.ed, l.ein, l.atk,
        d.uid IS NOT NULL AS matched, CASE WHEN c.uid IS NOT NULL THEN 'cid' WHEN f.uid IS NOT NULL THEN 'owner' END AS src,
        d.dt, d.how, d.paid, d.by_pid, coalesce(d.by_pid = l.pid AND d.how IN ('lh', 'deny'), 0) AS mine,
        l.walk = 0 AS inrange, l.ein > 0 AND l.ed > l.md AS outdmg, l.eh > 0 AS covered,
        CASE WHEN l.want = 1 THEN round(l.slot + l.wo, 1) END AS snap
    FROM co_l l
    LEFT JOIN co_c c ON c.game_id = l.game_id AND c.seq = l.seq
    LEFT JOIN co_f f ON f.game_id = l.game_id AND f.seq = l.seq
    LEFT JOIN (SELECT game_id, seq, uid, dt, how, paid, by_pid FROM co_c
        UNION ALL SELECT game_id, seq, uid, dt, how, paid, by_pid FROM co_f) d ON d.game_id = l.game_id AND d.seq = l.seq
),
