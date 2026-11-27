-- The decider's begins by row and by the mode the hero was taken from (master docs/proposals/2026-11-27-offers-and-the-decider.md
-- s10, slice A): one row per batch, arm, side, role, row begun (`beg`) and mode (`bfrom`, read inside the begin; logs before
-- oha-start-from have none and show `-`). A begin is an `ev=choice kind=decider` line with `beg`; `over` names a task it replaced.
-- Columns: batch, arm, side (test or opp against the label's seat; NULL with no seat, both teams together), role (core: lineup
-- pos 1-3; support: 4-5; NULL for a hero with no lineup pos), beg, bfrom, n (begins), fight (1 when bfrom is attack, roam or
-- team_roam: the modes slice A refuses a start from), held_s (the seconds those begins held the hero: from the begin to the hero's
-- next decider line that holds another row or none, or begins again; within one round, 0.32 s, of the task's end), team_games
-- (games x teams read in the group), per_tg (n / team_games), held_tg (held_s / team_games). Slice A's line (user 27/11/2026): the
-- fight rows' held_tg, on against off.
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600, the
-- line's t). A second a game.
-- ensure: ev_choice(pid, kind, held, beg, bfrom, over, ref)
WITH gm AS MATERIALIZED (
    SELECT g.game_id, r.batch, r.arm, r.seat_team FROM games g JOIN run_label r ON r.game_id = g.game_id
    WHERE g.bots > 0 AND (g.file LIKE coalesce(:like, '') OR r.batch = :batch)
),
b AS (
    SELECT gm.batch, gm.arm, l.team, gm.seat_team, c.game_id,
        CASE WHEN l.pos BETWEEN 1 AND 3 THEN 'core' WHEN l.pos BETWEEN 4 AND 5 THEN 'support' END AS role,
        c.beg, coalesce(c.bfrom, '-') AS bfrom,
        (SELECT min(c2.t) FROM ev_choice c2 WHERE c2.game_id = c.game_id AND c2.pid = c.pid AND c2.t > c.t AND c2.kind = 'decider'
            AND c2.ref IS NULL AND (c2.beg IS NOT NULL OR c2.held <> c.beg)) - c.t AS held_s
    FROM ev_choice c JOIN gm ON gm.game_id = c.game_id
    LEFT JOIN lineup l ON l.game_id = c.game_id AND l.pid = c.pid
    WHERE c.kind = 'decider' AND c.beg IS NOT NULL
      AND c.t >= coalesce(:from, 0) AND c.t <= coalesce(:until, 600)
),
s AS (SELECT batch, arm, CASE WHEN seat_team IS NULL THEN NULL WHEN team = seat_team THEN 'test' ELSE 'opp' END AS side,
        role, beg, bfrom, held_s, game_id, team FROM b),
tg AS (
    SELECT gm.batch, gm.arm, CASE WHEN gm.seat_team IS NULL THEN NULL WHEN t.team = gm.seat_team THEN 'test' ELSE 'opp' END AS side,
        count(*) AS team_games
    FROM gm JOIN (SELECT 2 AS team UNION ALL SELECT 3) t
    GROUP BY 1, 2, 3
)
SELECT s.batch, s.arm, s.side, s.role, s.beg, s.bfrom, count(*) AS n,
    s.bfrom IN ('attack', 'roam', 'team_roam') AS fight, round(coalesce(sum(s.held_s), 0), 1) AS held_s, tg.team_games,
    round(1.0 * count(*) / tg.team_games, 2) AS per_tg, round(coalesce(sum(s.held_s), 0) / tg.team_games, 1) AS held_tg
FROM s JOIN tg ON tg.batch IS s.batch AND tg.arm IS s.arm AND tg.side IS s.side
GROUP BY s.batch, s.arm, s.side, s.role, s.beg, s.bfrom
ORDER BY s.batch, s.arm, s.side, s.role, s.beg, n DESC
