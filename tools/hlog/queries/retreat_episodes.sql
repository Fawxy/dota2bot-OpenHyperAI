-- Our retreat's episodes (slice retreat, master docs/team/slices/retreat.md; bot humaniser/retreat.ts): one row per
-- `ev=retreat kind=ours` episode in games whose file matches :like, its start joined to its end by (game, pid, ep).
--   why, hp, thr, band, reach, burst, tower, esc, budget, purp   the leave rule's read at the start
--   anchor, cost, alt, dist, spot, rep                          the anchor chosen, its route cost, the next-best one's, the walk;
--                                                               a forced drill rep's start spot and rep
--   res, secs, hpl, twr, wave, dmgh                             the end (null res: the game ended first)
--   back3   our next episode of the same hero started within 3 s of this end (a laning/retreat swap, the leave target's bar)
--   full    started over 0.8 HP
-- Params: like (file pattern), until (start time cap, default 600).
-- ensure: ev_retreat(ph, pid, kind, ep, why, hp, thr, band, reach, burst, tower, esc, budget, purp, anchor, cost, alt, dist, spot, rep, res, secs, hpl, twr, wave, dmgh)
WITH
gm AS MATERIALIZED (SELECT game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
st AS MATERIALIZED (
    SELECT r.game_id, r.pid, r.ep, r.t, r.why, r.hp, r.thr, r.band, r.reach, r.burst, r.tower, r.esc, r.budget, r.purp, r.anchor,
        r.cost, r.alt, r.dist, r.spot, r.rep
    FROM ev_retreat r JOIN gm USING (game_id)
    WHERE r.ph = 'start' AND r.kind = 'ours' AND r.t <= coalesce(:until, 600)
),
en AS MATERIALIZED (
    SELECT r.game_id, r.pid, r.ep, r.t, r.res, r.secs, r.hpl, r.twr, r.wave, r.dmgh
    FROM ev_retreat r JOIN gm USING (game_id) WHERE r.ph = 'end' AND r.kind = 'ours'
),
ep AS (
    SELECT st.*, en.t AS t_end, en.res, en.secs, en.hpl, en.twr, en.wave, en.dmgh,
        lead(st.t) OVER (PARTITION BY st.game_id, st.pid ORDER BY st.t) AS next_t
    FROM st LEFT JOIN en ON en.game_id = st.game_id AND en.pid = st.pid AND en.ep = st.ep
)
SELECT gm.file, ep.pid, l.pos, round(ep.t, 1) AS t, ep.why, ep.hp, ep.thr, ep.band, ep.reach, ep.burst, ep.tower, ep.esc, ep.budget,
    ep.purp, ep.anchor, ep.cost, ep.alt, ep.dist, ep.spot, ep.rep, ep.res, ep.secs, ep.hpl, ep.twr, ep.wave, ep.dmgh,
    CASE WHEN ep.t_end IS NOT NULL AND ep.next_t IS NOT NULL AND ep.next_t - ep.t_end <= 3 THEN 1 ELSE 0 END AS back3,
    CASE WHEN ep.hp > 0.8 THEN 1 ELSE 0 END AS full
FROM ep JOIN gm USING (game_id) LEFT JOIN lineup l ON l.game_id = ep.game_id AND l.pid = ep.pid
ORDER BY gm.file, ep.t
