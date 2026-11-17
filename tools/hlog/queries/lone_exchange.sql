-- The lone mid's even exchange (ROADMAP row 2, plan hit-back-into-trade step 5a): one row per episode of our pos 2's
-- `cut kind=trade` answers in the situation (one enemy hero in reach, no ally near (`ally` counts the hero itself), our HP at `minhp` or more, `dec` the
-- answer: `unfavoured` held, `trade` taken), episodes by hero pair a gap of more than 8 s apart, to `until`. Beside the
-- cut: ko, kt (kill shares), our and the target's raw HP at the episode's first cut and 8 s later (`my_lost`, `t_lost`:
-- what each lost; below 0 for the exchange going our way), `my_died` / `t_died` (deaths counter up within 20 s), `hit`
-- (we were hit by a hero in the 8 s). Params: like, minhp (default 0.7), until (default 720), dec (default unfavoured).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
who AS (
    SELECT game_id, pid, pos FROM (
        SELECT b.game_id, b.pid, b.pos, row_number() OVER (PARTITION BY b.game_id, b.pid ORDER BY b.seq DESC) AS rn
        FROM ev_bot b JOIN gm ON gm.game_id = b.game_id WHERE b.pos IS NOT NULL) WHERE rn = 1),
c AS (
    SELECT c.game_id, c.pid, c.tgt, c.t, c.ko, c.kt, c.hp, c.bu, c.dec,
        lag(c.t) OVER (PARTITION BY c.game_id, c.pid, c.tgt ORDER BY c.t) AS pt
    FROM ev_cut c JOIN gm ON gm.game_id = c.game_id JOIN who w ON w.game_id = c.game_id AND w.pid = c.pid AND w.pos = 2
    WHERE c.kind = 'trade' AND c.dec = coalesce(:dec, 'unfavoured') AND c.en = 1 AND c.ally <= 1 AND c.hp >= coalesce(:minhp, 0.7)
        AND c.t >= 90 AND c.t <= coalesce(:until, 720) AND c.tgt IS NOT NULL),
e AS (SELECT * FROM c WHERE pt IS NULL OR t - pt > 8),
sn AS (
    SELECT e.game_id, e.pid, e.tgt, e.t, e.ko, e.kt, e.hp, e.bu,
        (SELECT s.hv FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= e.t ORDER BY s.t DESC LIMIT 1) AS m0,
        (SELECT s.hv FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= e.t + 8 ORDER BY s.t DESC LIMIT 1) AS m8,
        (SELECT s.hv FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.tgt AND s.t <= e.t ORDER BY s.t DESC LIMIT 1) AS h0,
        (SELECT s.hv FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.tgt AND s.t <= e.t + 8 ORDER BY s.t DESC LIMIT 1) AS h8,
        (SELECT max(s.deaths) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= e.t + 20)
            - (SELECT max(s.deaths) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t <= e.t) AS md,
        (SELECT max(s.deaths) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.tgt AND s.t <= e.t + 20)
            - (SELECT max(s.deaths) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.tgt AND s.t <= e.t) AS td,
        (SELECT max(coalesce(s.hit, 0)) FROM ev_snap s WHERE s.game_id = e.game_id AND s.pid = e.pid AND s.t > e.t AND s.t <= e.t + 8) AS hit
    FROM e)
SELECT game_id, pid, tgt, CAST(t AS INTEGER) AS t, ko, kt, CASE WHEN kt > 0 THEN round(ko / kt, 2) END AS ratio, hp, bu,
    m0 - m8 AS my_lost, h0 - h8 AS t_lost, coalesce(md, 0) > 0 AS my_died, coalesce(td, 0) > 0 AS t_died, hit
FROM sn ORDER BY game_id, t
