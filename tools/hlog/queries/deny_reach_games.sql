-- Lane denies line, per team-game (family lane denies, master docs/proposals/2026-11-24-next-three-families.md s6): of the own
-- lane creeps that died with a side-lane support in reach (fragment deny_reach_rows, band `in`), the share our side denied, the
-- support's own share and the enemy's last-hit share; the same for band `near` (just outside reach: an outcome count, never
-- the line). The line is `den_share` on band in, read per team-game and paired by seed, lineup and seat.
-- Columns: file, game, team, band, n, sup (support denies), den (all own denies), elh (enemy last hits), den_share, sup_share,
-- elh_share.
-- Params: like (a path fragment or run label; required), until (default 600). About 3 s a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '') AND bots > 0),
-- include: deny_reach_rows
SELECT gm.file, gm.game, r.team, r.band, count(*) AS n,
    sum(r.fate = 'sup_deny') AS sup, sum(r.fate IN ('sup_deny', 'own_deny')) AS den, sum(r.fate = 'enemy_lh') AS elh,
    round(avg(r.fate IN ('sup_deny', 'own_deny')), 3) AS den_share, round(avg(r.fate = 'sup_deny'), 3) AS sup_share,
    round(avg(r.fate = 'enemy_lh'), 3) AS elh_share
FROM deny_reach_rows r JOIN gm USING (game_id)
GROUP BY gm.file, gm.game, r.team, r.band
ORDER BY r.band, gm.file, gm.game, r.team
