-- Enemy lane creeps our own towers were attacking when they died (row "Last-hit refinement" step 1, the pre-hit decision):
-- per game and logging team, ev=creep_death to :until (default 600) in games whose file matches :like. `tw` (bot build from
-- slice lasthit-refine-logs on) is 1 when one of the team's towers was attacking the creep on the frame before it died.
-- `deaths` all logged enemy creep deaths; `tw_deaths` those with tw=1; `tower` tw=1 and fate `other` (no one's last hit or deny:
-- the tower's kill, or a creep's in the same frame); `tower_reach` of those, the ones with one of our cores (pos 1-3) within its
-- attack range + 100 (the creeps a pre-hit could have won); `tw_lh` tw=1 and our last hit (won under the tower already);
-- `tw_denied` tw=1 and an enemy deny. `untagged` deaths with no tw field (an older build: leave those games out).
-- Pre-hit is worth building only if `tower_reach` is about 2 or more per team per 10:00 (proposal 2026-11-04-prehit-and-feints).
-- ensure: ev_creep_death(team, kind, x, y, by, tw, p1d, p1r, p2d, p2r, p3d, p3r)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
d AS (
    SELECT c.game_id, c.team, c.tw, f.fate,
        (c.p1d IS NOT NULL AND c.p1d <= c.p1r + 100) OR (c.p2d IS NOT NULL AND c.p2d <= c.p2r + 100)
            OR (c.p3d IS NOT NULL AND c.p3d <= c.p3r + 100) AS reach
    FROM ev_creep_death c
    JOIN creep_fate f ON f.game_id = c.game_id AND f.seq = c.seq AND f.side = 'enemy'
    WHERE c.game_id IN (SELECT game_id FROM gm) AND c.t < coalesce(:until, 600)
)
SELECT gm.file, d.game_id, d.team,
    count(*) AS deaths,
    sum(d.tw = 1) AS tw_deaths,
    sum(d.tw = 1 AND d.fate = 'other') AS tower,
    sum(d.tw = 1 AND d.fate = 'other' AND d.reach) AS tower_reach,
    sum(d.tw = 1 AND d.fate = 'own_lh') AS tw_lh,
    sum(d.tw = 1 AND d.fate = 'enemy_deny') AS tw_denied,
    sum(d.tw IS NULL) AS untagged
FROM d JOIN gm ON gm.game_id = d.game_id
GROUP BY d.game_id, d.team
ORDER BY d.game_id, d.team;
