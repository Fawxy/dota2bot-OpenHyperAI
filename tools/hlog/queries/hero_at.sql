-- One hero's state at a clock: the last ev=snap, the last ev=inv and (in a drill game) the last drill rep, each at or before t.
-- Params: like (log path pattern, default all logs), game (default 1; remote-batch logs need game=2), pid or hero (a name as in ev=bot), t (seconds, or m:ss).
-- Row: snap_t (age = t - snap_t), alive hp mp lvl gold nw x y mode by act tgt tid, inv_t and inv (`s<slot>=<item>[:<charges>]`; NULL for a log from before ev=inv),
-- drill rep input. A hero with no snap by t gives a row with the snap columns NULL. Fast because each join filters on the store's (game_id, pid, t) index (ev_snap and ev_inv both have it); `m:ss` may be negative (-1:30 is -90).
-- ensure: ev_snap(pid, alive, hp, mp, lvl, gold, nw, x, y, mode, by, act, tgt, tid)
-- ensure: ev_inv(pid, items)
-- ensure: ev_drill(ph, name, rep, input)
WITH q AS (
    SELECT CASE WHEN :t LIKE '%:%' THEN (CASE WHEN :t LIKE '-%' THEN -1 ELSE 1 END) *
        (abs(cast(substr(:t, 1, instr(:t, ':') - 1) AS INTEGER)) * 60 + cast(substr(:t, instr(:t, ':') + 1) AS REAL))
        ELSE :t END AS t
),
w AS (
    SELECT g.game_id, g.file, g.game,
        coalesce(:pid, (SELECT n.pid FROM hero_names n WHERE n.game_id = g.game_id AND n.hero = :hero)) AS pid
    FROM (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '%') AND game = coalesce(:game, 1)) g
),
s AS (
    SELECT w.game_id, e.t, e.alive, e.hp, e.mp, e.lvl, e.gold, e.nw, e.x, e.y, e.mode, e."by", e.act, e.tgt, e.tid,
        row_number() OVER (PARTITION BY w.game_id ORDER BY e.t DESC, e.seq DESC) AS rn
    FROM w JOIN ev_snap e ON e.game_id = w.game_id AND e.pid = w.pid AND e.t <= (SELECT t FROM q)
),
i AS (
    SELECT w.game_id, e.t, e.items,
        row_number() OVER (PARTITION BY w.game_id ORDER BY e.t DESC, e.seq DESC) AS rn
    FROM w JOIN ev_inv e ON e.game_id = w.game_id AND e.pid = w.pid AND e.t <= (SELECT t FROM q)
),
d AS (
    SELECT w.game_id, e.t, e.name, e.rep, e.input,
        row_number() OVER (PARTITION BY w.game_id ORDER BY e.t DESC, e.seq DESC) AS rn
    FROM w JOIN ev_drill e ON e.game_id = w.game_id AND e.ph = 'rep' AND e.t <= (SELECT t FROM q)
)
SELECT w.file, w.game, w.pid,
    (SELECT n.hero FROM hero_names n WHERE n.game_id = w.game_id AND n.pid = w.pid) AS hero,
    (SELECT t FROM q) AS t,
    s.t AS snap_t, s.alive, s.hp, s.mp, s.lvl, s.gold, s.nw, s.x, s.y, s.mode, s."by", s.act, s.tgt, s.tid,
    i.t AS inv_t, i.items AS inv,
    d.name AS drill, d.rep, d.input
FROM w
LEFT JOIN s ON s.game_id = w.game_id AND s.rn = 1
LEFT JOIN i ON i.game_id = w.game_id AND i.rn = 1
LEFT JOIN d ON d.game_id = w.game_id AND d.rn = 1
WHERE w.pid IS NOT NULL
ORDER BY w.file
