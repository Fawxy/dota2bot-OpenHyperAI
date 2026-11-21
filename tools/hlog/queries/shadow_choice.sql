-- The shadow choice line (ev=choice kind=shadow, Ours.ChoiceShadow): per run label and hero, seconds by what the line says.
-- A row is one (label, hero, part, mode, cause):
--   part `lost`: seconds OHA's own computed desires picked `mode` (attack, team_roam or roam; `top`) while Valve held the
--     hero in another mode (`win`); cause is the line's `how by` (the module of ours that made the difference).
--   part `unread`: seconds `mode`'s own desire was not computed (`d_<mode>` a `-<reason>`); cause is the reason.
--   part `win`: seconds Valve held the hero in `mode` (to compare with ev_snap `mode`).
-- Each line counts until the hero's next line, at most 2 s. Params: like (LIKE pattern on games.file or a label), from,
-- until (seconds, default 0 and 720), part (one part, default all).
WITH gm AS MATERIALIZED (
    SELECT +game_id AS game_id, label FROM games
    WHERE file LIKE coalesce(:like, '%') OR label LIKE coalesce(:like, '%')
),
c AS MATERIALIZED (
    SELECT c.game_id, gm.label, c.pid, c.t, c.win, c.top, c.tv, c.how, c.by, c.d_attack, c.d_team_roam, c.d_roam,
        min(coalesce(lead(c.t) OVER (PARTITION BY c.game_id, c.pid ORDER BY c.t, c.seq), c.t) - c.t, 2.0) AS dt
    FROM ev_choice c JOIN gm ON gm.game_id = c.game_id
    WHERE c.kind = 'shadow' AND c.t >= coalesce(:from, 0) AND c.t <= coalesce(:until, 720)
),
r AS (
    SELECT game_id, label, pid, 'lost' AS part, top AS mode, coalesce(how || ' ' || by, '?') AS cause, dt FROM c
    WHERE top IN ('attack', 'team_roam', 'roam') AND win <> top AND tv > 0
    UNION ALL SELECT game_id, label, pid, 'unread', 'attack', substr(d_attack, 2), dt FROM c WHERE typeof(d_attack) = 'text'
    UNION ALL SELECT game_id, label, pid, 'unread', 'team_roam', substr(d_team_roam, 2), dt FROM c WHERE typeof(d_team_roam) = 'text'
    UNION ALL SELECT game_id, label, pid, 'unread', 'roam', substr(d_roam, 2), dt FROM c WHERE typeof(d_roam) = 'text'
    UNION ALL SELECT game_id, label, pid, 'win', win, NULL, dt FROM c
)
SELECT r.label, coalesce(h.hero, 'pid' || r.pid) AS hero, r.part, r.mode, r.cause, round(sum(r.dt), 1) AS secs
FROM r LEFT JOIN hero_names h ON h.game_id = r.game_id AND h.pid = r.pid
WHERE :part IS NULL OR r.part = :part
GROUP BY r.label, r.pid, h.hero, r.part, r.mode, r.cause
ORDER BY r.label, r.pid, r.part, secs DESC, r.mode, r.cause
