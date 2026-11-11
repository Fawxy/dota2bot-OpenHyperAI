-- The games line for D1, D2, D3, D7, D9, D24 and D24h (D24's hit-back half; DOCTRINE.md "Games"): per game and side, the situations found (`_n`) and the
-- violations (`_v`) of each rule, and the side's deaths to :until (fragment lane_rules has the rules; @rule_cases lists the
-- cases with causes). D24h also carries its answers: `d24h_hb` (hit back, the right action) and `d24h_left` (left, a
-- violation) of `d24h_n`. Params: like, until (default 720).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
sides AS (SELECT game_id, team, max(side) AS side FROM lr_who GROUP BY game_id, team),
dth AS (
    SELECT w.game_id, w.team, count(*) AS deaths FROM lr_death d JOIN lr_who w ON w.game_id = d.game_id AND w.pid = d.pid
    WHERE d.dsec <= coalesce(:until, 720) GROUP BY w.game_id, w.team
)
SELECT gm.file, s.side, s.team,
    coalesce(sum(c.rule = 'D1'), 0) AS d1_n, coalesce(sum(c.rule = 'D1' AND c.viol), 0) AS d1_v,
    coalesce(sum(c.rule = 'D2'), 0) AS d2_v,
    coalesce(sum(c.rule = 'D3'), 0) AS d3_n, coalesce(sum(c.rule = 'D3' AND c.viol), 0) AS d3_v,
    coalesce(sum(c.rule = 'D7'), 0) AS d7_n, coalesce(sum(c.rule = 'D7' AND c.viol), 0) AS d7_v,
    coalesce(sum(c.rule = 'D9'), 0) AS d9_n, coalesce(sum(c.rule = 'D9' AND c.viol), 0) AS d9_v,
    coalesce(sum(c.rule = 'D24'), 0) AS d24_n, coalesce(sum(c.rule = 'D24' AND c.viol), 0) AS d24_v,
    coalesce(sum(c.rule = 'D24h'), 0) AS d24h_n, coalesce(sum(c.rule = 'D24h' AND c.viol), 0) AS d24h_v,
    coalesce(sum(c.rule = 'D24h' AND c.cause = 'hit_back'), 0) AS d24h_hb, coalesce(sum(c.rule = 'D24h' AND c.cause = 'left'), 0) AS d24h_left,
    coalesce((SELECT deaths FROM dth WHERE dth.game_id = s.game_id AND dth.team = s.team), 0) AS deaths
FROM sides s JOIN gm ON gm.game_id = s.game_id
LEFT JOIN lr_case c ON c.game_id = s.game_id AND c.team = s.team
GROUP BY s.game_id, s.team
ORDER BY gm.file, s.team
