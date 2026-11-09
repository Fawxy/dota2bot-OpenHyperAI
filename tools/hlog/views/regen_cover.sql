-- Regen coverage (slice regen): per game and item, the windows in which the item could have been used and how many had a use
-- inside, from ev=regen_win (both arms, whoever used it). A window counts for an item when it is in hand, the HP missing at some point
-- in the window reaches that item's full effect (`tge`, `sve`, read from the item), no tango or salve was already running, and for a
-- tango a visible, passable tree lay within 600 at the window's start (`judgement`: the verb's own budget is the caller's; the same
-- bound grades both arms). `used` names the item whose buff started inside the window. `miss_share` = 1 - used / windows.
-- Faerie fire is not here yet (its use leaves no buff to observe; the OHA use-site note comes with the hooks).
-- needs: ev_regen_win(pid, len, missmax, tg, sv, tge, sve, tree, under, used)
SELECT w.game_id, g.file, g.game, 'tango' AS item, count(*) AS windows,
    sum(CASE WHEN w."used" LIKE '%tango%' THEN 1 ELSE 0 END) AS used_n,
    1.0 - 1.0 * sum(CASE WHEN w."used" LIKE '%tango%' THEN 1 ELSE 0 END) / count(*) AS miss_share
FROM ev_regen_win w JOIN games g USING (game_id)
WHERE w.tg > 0 AND w.missmax >= w.tge AND w.tree >= 0 AND w.tree <= 600 AND w."under" = 0
GROUP BY w.game_id
UNION ALL
SELECT w.game_id, g.file, g.game, 'salve' AS item, count(*) AS windows,
    sum(CASE WHEN w."used" LIKE '%salve%' THEN 1 ELSE 0 END) AS used_n,
    1.0 - 1.0 * sum(CASE WHEN w."used" LIKE '%salve%' THEN 1 ELSE 0 END) / count(*) AS miss_share
FROM ev_regen_win w JOIN games g USING (game_id)
WHERE w.sv > 0 AND w.missmax >= w.sve AND w."under" = 0
GROUP BY w.game_id
