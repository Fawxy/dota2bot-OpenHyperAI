-- Rune spawns (family rune trips, master docs/proposals/2026-11-24-next-three-families.md s7): one row per rune spawn from 0:01 to
-- :until and who took it. Found from what happened (ev=rune_pickup, which both teams log for their own takers), never from our own
-- read, so it runs on both arms and on stock.
--   spawns  the rule's times (game_rules.ts RUNE_RULES; docs/reference/specifics/runes-and-shrines.md): water at 2:00 and 4:00 on
--           both river spots (rune 0 top, 1 bot); power from 6:00 every 2:00 on one river spot (which one is not logged unless
--           it is taken: spot null when untaken; a pickup on either spot in the window is that spawn's); bounty from 4:00 every
--           4:00 on each jungle spot (rune 2 Dire's jungle, 3 Radiant's; 4 and 5 log no pickup in any banked game).
--           The 0:00 bounties are not here: ev=rune_pickup starts at 0:01 (telemetry RUNES_FROM) and they are taken in the first
--           second; gold.js infers them (start_0:00), not a pickup.
--   window  a spawn's pickup is the first on its spot (power: either river spot) from the spawn to the kind's next spawn; a
--           river rune left there is gone by then (power and water despawn), a bounty is assumed replaced (`judgement`).
--   res     taken (by team, pid), untaken (no pickup in the window). own 1 when a jungle bounty went to that jungle's side,
--           null on river runes.
-- Columns: file, game, kind, sp (spawn second), rune (null: an untaken power rune), side (rad, dire, river), t (pickup), dt (t - sp),
-- team, pid, pos, hero, res, own.
-- Params: like (a path fragment or run label; required), until (spawns before it, default 600).
-- ensure: ev_rune_pickup(pid, team, rune, kind)
-- ensure: ev_bot(pid, team, pos, hero)
WITH RECURSIVE
gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '') AND bots > 0),
tick(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM tick WHERE n < 30),
sched AS (
    SELECT 'water' AS kind, s.r AS rune, 120 * (t.n + 1) AS sp, 120 AS every FROM tick t, (SELECT 0 AS r UNION ALL SELECT 1) s
        WHERE 120 * (t.n + 1) <= 240
    UNION ALL SELECT 'power', NULL, 360 + 120 * t.n, 120 FROM tick t
    UNION ALL SELECT 'bounty', s.r, 240 * (t.n + 1), 240 FROM tick t, (SELECT 2 AS r UNION ALL SELECT 3) s
),
sp AS MATERIALIZED (SELECT gm.game_id, sc.* FROM gm, sched sc WHERE sc.sp < coalesce(:until, 600)),
pk AS MATERIALIZED (
    SELECT p.game_id, p.t, p.team, p.pid, p.rune, p.kind FROM ev_rune_pickup p JOIN gm USING (game_id)
    WHERE p.t >= 1 AND p.t < coalesce(:until, 600) + 240
),
hit AS (
    SELECT s.game_id, s.kind, s.sp, s.rune AS srune, s.every,
        (SELECT p.t FROM pk p WHERE p.game_id = s.game_id AND p.t >= s.sp AND p.t < s.sp + s.every
            AND (CASE WHEN s.rune IS NULL THEN p.rune IN (0, 1) ELSE p.rune = s.rune END)
            ORDER BY p.t LIMIT 1) AS t
    FROM sp s
),
hb AS (SELECT game_id, pid, max(team) AS team, max(pos) AS pos, max(hero) AS hero FROM ev_bot GROUP BY game_id, pid)
SELECT gm.file, gm.game, h.kind, h.sp, coalesce(h.srune, p.rune) AS rune,
    CASE coalesce(h.srune, p.rune) WHEN 2 THEN 'dire' WHEN 3 THEN 'rad' ELSE 'river' END AS side,
    p.t, round(p.t - h.sp, 1) AS dt, p.team, p.pid, b.pos, b.hero,
    CASE WHEN p.t IS NULL THEN 'untaken' ELSE 'taken' END AS res,
    CASE WHEN h.kind <> 'bounty' OR p.t IS NULL THEN NULL WHEN p.team = CASE h.srune WHEN 3 THEN 2 ELSE 3 END THEN 1 ELSE 0 END AS own
FROM hit h JOIN gm USING (game_id)
LEFT JOIN pk p ON p.game_id = h.game_id AND p.t = h.t
    AND (CASE WHEN h.srune IS NULL THEN p.rune IN (0, 1) ELSE p.rune = h.srune END)
LEFT JOIN hb b ON b.game_id = p.game_id AND b.pid = p.pid
ORDER BY gm.file, gm.game, h.sp, h.kind, rune
