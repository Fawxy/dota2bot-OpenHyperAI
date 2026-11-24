-- Lane denies line, rows (family lane denies, master docs/proposals/2026-11-24-next-three-families.md s6): one row per own lane
-- creep that died with a pos 4 or 5 of its team in or just outside reach, and who took it. The unit, bands and fates are the
-- fragment deny_reach_rows's. Per team-game counts: `q @deny_reach_games`.
-- Columns: file, game, t, team, kind, pid (the nearer support), pos, ln, dist, ar, offers (that snap's `od`), band, fate.
-- Params: like (a path fragment or run label; required), until (deaths before it, default 600). About 3 s a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '') AND bots > 0),
-- include: deny_reach_rows
SELECT gm.file, gm.game, r.t, r.team, r.kind, r.pid, r.pos, r.ln, r.dist, r.ar, r.offers, r.band, r.fate
FROM deny_reach_rows r JOIN gm USING (game_id)
ORDER BY gm.file, gm.game, r.t, r.team
