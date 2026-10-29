-- One row per hero per game minute: the last ev=snap of that minute (pre-game snaps count as minute 0 or below).
-- The laning bars read lh/dn/kills/deaths at minutes 2, 5 and 10 from here; human heroes are included (human=1).
-- needs: ev_snap(pid, human, lh, dn, kills, deaths, gold, lvl, hp, alive)
SELECT s.game_id, g.file, g.game, s.pid, s.human,
    CAST(s.t + 6000 AS INTEGER) / 60 - 100 AS minute,
    max(s.t) AS t, s.lh, s.dn, s.kills, s.deaths, s.gold, s.lvl, s.hp, s.alive
FROM ev_snap s JOIN games g USING (game_id)
GROUP BY s.game_id, s.pid, CAST(s.t + 6000 AS INTEGER) / 60 - 100
