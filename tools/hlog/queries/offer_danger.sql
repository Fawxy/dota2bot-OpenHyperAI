-- The danger shadow (master docs/proposals/2026-11-27-offers-and-the-decider.md s5, slice oha-offer-danger): one row per begun
-- offer that named a place, its danger parts at the begin (`ev=choice kind=decider` with `beg` and `bsec`, Danger.At) beside what
-- happened in its window. Columns: file, game, batch, arm, pid, pos (lineup), t, beg (the row), btgt, bway, bfrom, bsec (the window
-- asked, s), dn (visible enemy heroes reaching the walk), dre (`pid:dist:exp:dmg` each), dbu (their damage as a share of HP), dal
-- (our heroes reaching the place), dtw (enemy tower cover), dun (`pid:tss:dist` each unseen), dnos (never sighted), dfail (1 when
-- Danger.At failed: no parts and no window, its outcome columns 0); hero_loss: HP-% points lost to heroes in (t, t + bsec] (view
-- hp_loss, any basis; the second at t is the begin's own, before it; a second whose `src` names a hero among several sources counts
-- its share, split evenly, as lane_score's hpl_hero), loss: HP-% points lost to anything there; died: 1 when the hero died in
-- (t, t + bsec + 5].
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600).
-- ensure: ev_choice(pid, kind, beg, btgt, bway, bfrom, bsec, dn, dre, dbu, dal, dtw, dun, dnos, dfail)
WITH gm AS MATERIALIZED (
    SELECT g.game_id, g.file, g.game, r.batch, r.arm FROM games g LEFT JOIN run_label r ON r.game_id = g.game_id
    WHERE g.bots > 0 AND (g.file LIKE coalesce(:like, '') OR r.batch = :batch)
),
b AS MATERIALIZED (
    SELECT gm.game_id, gm.file, gm.game, gm.batch, gm.arm, c.pid, c.t, c.beg, c.btgt, c.bway, c.bfrom, c.bsec,
        c.dn, c.dre, c.dbu, c.dal, c.dtw, c.dun, c.dnos, c.dfail
    FROM ev_choice c JOIN gm ON gm.game_id = c.game_id
    WHERE c.kind = 'decider' AND c.beg IS NOT NULL AND (c.bsec IS NOT NULL OR c.dfail = 1)
      AND c.t >= coalesce(:from, 0) AND c.t <= coalesce(:until, 600)
),
h AS MATERIALIZED (
    SELECT game_id, pid, t, died, loss,
        ('+' || src || '+') LIKE '%+hero%' AS by_hero, length(src) - length(replace(src, '+', '')) + 1 AS nsrc
    FROM hp_loss WHERE game_id IN (SELECT game_id FROM gm)
)
SELECT b.file, b.game, b.batch, b.arm, b.pid, l.pos, round(b.t, 1) AS t, b.beg, b.btgt, b.bway, b.bfrom, b.bsec,
    b.dn, b.dre, b.dbu, b.dal, b.dtw, b.dun, b.dnos, b.dfail,
    round(coalesce((SELECT sum(1.0 * h.loss / h.nsrc) FROM h WHERE h.game_id = b.game_id AND h.pid = b.pid AND NOT h.died
        AND h.t > b.t AND h.t <= b.t + b.bsec AND h.by_hero), 0), 1) AS hero_loss,
    round(coalesce((SELECT sum(h.loss) FROM h WHERE h.game_id = b.game_id AND h.pid = b.pid AND NOT h.died
        AND h.t > b.t AND h.t <= b.t + b.bsec), 0), 1) AS loss,
    EXISTS (SELECT 1 FROM h WHERE h.game_id = b.game_id AND h.pid = b.pid AND h.died
        AND h.t > b.t AND h.t <= b.t + b.bsec + 5) AS died
FROM b LEFT JOIN lineup l ON l.game_id = b.game_id AND l.pid = b.pid
ORDER BY b.file, b.game, b.t, b.pid
