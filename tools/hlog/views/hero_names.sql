-- Hero name per game and pid: the last ev=bot or ev=player line wins (as front.js did). ev_player exists only in logs with a
-- human, so the store creates it empty when no log has one.
-- ensure: ev_bot(pid, hero)
-- ensure: ev_player(pid, hero)
SELECT game_id, pid, hero FROM (
    SELECT game_id, pid, hero, row_number() OVER (PARTITION BY game_id, pid ORDER BY seq DESC) AS rn
    FROM (SELECT game_id, seq, pid, hero FROM ev_bot UNION ALL SELECT game_id, seq, pid, hero FROM ev_player)
) WHERE rn = 1
