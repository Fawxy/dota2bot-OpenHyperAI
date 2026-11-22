-- Each game's run label read as its parts, to join to any query: `JOIN run_label r USING (game_id)`.
-- Columns: game_id, label, batch (the run name: `base1` is not `h2hbase1`), lineup (A, B, C), arm, seat (rad or dire: the
-- side our arm played; NULL for a stock arm or a label naming none), seat_team (2 or 3), rep (the repetition number).
-- A label that does not say a part gives NULL for it; the parser is label.js (shapes it does not read are listed there).
SELECT game_id, label,
    run_label_part(label, 'batch') AS batch, run_label_part(label, 'lineup') AS lineup, run_label_part(label, 'arm') AS arm,
    run_label_part(label, 'seat') AS seat,
    CASE run_label_part(label, 'seat') WHEN 'rad' THEN 2 WHEN 'dire' THEN 3 END AS seat_team,
    run_label_part(label, 'rep') AS rep
FROM games
