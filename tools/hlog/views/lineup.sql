-- Lineup position per hero (1 = safe-lane core ... 5): the last ev=bot with a pos; where two heroes of a team share a position the
-- higher pid wins (as lasthit_cause.js did). Human heroes have no ev=bot, so they are not here.
-- ensure: ev_bot(pid, team, pos)
SELECT game_id, team, pos, max(pid) AS pid
FROM (
    SELECT game_id, pid, team, pos, row_number() OVER (PARTITION BY game_id, pid ORDER BY seq DESC) AS rn
    FROM ev_bot WHERE pos IS NOT NULL AND team IS NOT NULL
)
WHERE rn = 1
GROUP BY game_id, team, pos
