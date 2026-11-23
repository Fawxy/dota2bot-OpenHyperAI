-- Regen episodes (family regen, master docs/proposals/2026-11-24-next-three-families.md s4): one row per time a hero of ours falls
-- under half HP in its own lane before :until, and how it ended. Found from what happened (hero_sec: HP percent, place, life), never
-- from our own read, so it runs on both arms and on stock.
--   onset  a live second in the hero's own lane (team and pos as GetAssignedLane gives it: pos 2 mid; Radiant pos 1 and 5 bot, 3
--          and 4 top; Dire the other way) with HP under 50% where its live second before had 50% or more (or it is the first)
--   end    the first later second, whatever the place, that is one of, in this order:
--            death     the hero is not live (dead, HP 0) or its life counter has risen
--            fountain  within 1,200 of its own fountain (the radius ep_death uses; `judgement`), any HP
--            lane      HP back to 50% or more in its own lane
--            away      HP back to 50% or more anywhere else (another lane, the jungle, base outside the fountain's radius)
--          open: none before :until + 300 or the log's end
-- Columns: file, game, pid, team, pos, hero, t0 (onset second), hp0, t1, secs (t1 - t0), res; back the first live second from t1
-- in its own lane (null: none by :until + 300); off_s the seconds from t0 to back (to :until + 300 when none) it was not live in its
-- own lane, the lane time the episode cost (0 for most `lane` ends); held tango charges (tg), salves (sv), clarities (cl) and faerie fires (ff) in hand (slots 0-5) at the
-- onset, from its latest ev=inv line; used: the tango, salve or clarity buffs that started inside it (ev=regen_obs state=start,
-- `,`-joined, - for none); unused 1 when a tango or salve was held at the onset and neither started inside; win the fit windows
-- (ev=regen_win, view regen_cover's rule for either item, in any mode) starting inside it, win_used those with a use.
-- use_t the first of those starts. gate the first second inside it (from t0, before t1) at which the regen group's gate holds:
-- a tango or salve held at the onset whose full restore fits in the HP missing (ev=snap hpm and hp), and no hero damage in that
-- second or the 2 before it (ev=snap hit, the API's flag for the last second: so 3 s). The restores are the game's ev=regen_win
-- tge and sve (read from the item), else 112 and 390 (7.41's tango and salve, `api` as the observer read them on stockbase2).
-- An opportunity the gate would have taken is gate not null and (use_t null or use_t >= gate).
-- ev=regen_obs and ev=regen_win are our observer's (regen_obs.ts): a build without it (OHA's own tree) reads used - and win 0.
-- Params: like (a path fragment or run label; required), until (onset time cap, default 600).
-- ensure: ev_inv(pid, items)
-- ensure: ev_regen_obs(pid, item, state)
-- ensure: ev_regen_win(pid, missmax, tg, sv, tge, sve, tree, under, used)
WITH
gm AS MATERIALIZED (SELECT game_id, file, game FROM games WHERE file LIKE coalesce(:like, '')),
hs AS MATERIALIZED (
    SELECT h.game_id, h.pid, h.team, h.pos, h.hero, h.sec, h.x, h.y, h.hp, h.live, h.life, h.lane,
        CASE WHEN h.pos = 2 THEN 'mid'
             WHEN h.pos IN (1, 5) THEN CASE h.team WHEN 2 THEN 'bot' ELSE 'top' END
             WHEN h.pos IN (3, 4) THEN CASE h.team WHEN 2 THEN 'top' ELSE 'bot' END END AS own,
        CASE h.team WHEN 2 THEN (h.x + 6700) * (h.x + 6700) + (h.y + 6700) * (h.y + 6700)
                    ELSE (h.x - 6928) * (h.x - 6928) + (h.y - 6372) * (h.y - 6372) END <= 1200 * 1200 AS fount
    FROM hero_sec h JOIN gm USING (game_id)
    WHERE h.sec >= 0 AND h.sec <= coalesce(:until, 600) + 300
),
lv AS (
    SELECT hs.*, lag(hs.hp) OVER (PARTITION BY hs.game_id, hs.pid ORDER BY hs.sec) AS hp_prev
    FROM hs WHERE hs.live
),
onset AS MATERIALIZED (
    SELECT game_id, pid, team, pos, hero, sec AS t0, hp AS hp0, life
    FROM lv
    WHERE hp < 50 AND lane = own AND sec <= coalesce(:until, 600) AND (hp_prev IS NULL OR hp_prev >= 50)
),
ended AS MATERIALIZED (
    SELECT o.*, (
        SELECT h.sec FROM hs h
        WHERE h.game_id = o.game_id AND h.pid = o.pid AND h.sec > o.t0
            AND (NOT h.live OR h.life > o.life OR h.fount OR h.hp >= 50)
        ORDER BY h.sec LIMIT 1) AS t1
    FROM onset o
),
res AS MATERIALIZED (
    SELECT e.*, CASE
        WHEN e.t1 IS NULL THEN 'open'
        WHEN NOT h.live OR h.life > e.life THEN 'death'
        WHEN h.fount THEN 'fountain'
        WHEN h.lane = h.own THEN 'lane'
        ELSE 'away' END AS res,
        (SELECT min(b.sec) FROM hs b WHERE b.game_id = e.game_id AND b.pid = e.pid AND b.sec >= e.t1
            AND b.live AND b.lane = b.own) AS back,
        (SELECT ' ' || i.items || ' ' FROM ev_inv i WHERE i.game_id = e.game_id AND i.pid = e.pid AND i.t <= e.t0
            ORDER BY i.t DESC, i.seq DESC LIMIT 1) AS inv
    FROM ended e LEFT JOIN hs h ON h.game_id = e.game_id AND h.pid = e.pid AND h.sec = e.t1
),
-- An inventory's hand slots (0-5) split into (slot, name, charges); a name with no charges counts 1.
tok (game_id, pid, t0, rest, slot, name, n) AS (
    SELECT game_id, pid, t0, ltrim(coalesce(inv, '')) , NULL, NULL, NULL FROM res
    UNION ALL
    SELECT game_id, pid, t0,
        ltrim(substr(rest, instr(rest || ' ', ' ') + 1)),
        CAST(substr(rest, 2, instr(rest, '=') - 2) AS INTEGER),
        CASE WHEN instr(substr(rest, 1, instr(rest || ' ', ' ') - 1), ':') > 0
             THEN substr(rest, instr(rest, '=') + 1, instr(rest, ':') - instr(rest, '=') - 1)
             ELSE substr(rest, instr(rest, '=') + 1, instr(rest || ' ', ' ') - instr(rest, '=') - 1) END,
        CASE WHEN instr(substr(rest, 1, instr(rest || ' ', ' ') - 1), ':') > 0
             THEN CAST(substr(rest, instr(rest, ':') + 1, instr(rest || ' ', ' ') - instr(rest, ':') - 1) AS INTEGER)
             ELSE 1 END
    FROM tok WHERE rest <> ''
),
held AS (
    SELECT game_id, pid, t0,
        sum(CASE WHEN name LIKE 'tango%' THEN n ELSE 0 END) AS tg,
        sum(CASE WHEN name = 'flask' THEN n ELSE 0 END) AS sv,
        sum(CASE WHEN name = 'clarity' THEN n ELSE 0 END) AS cl,
        sum(CASE WHEN name = 'faerie_fire' THEN n ELSE 0 END) AS ff
    FROM tok WHERE slot BETWEEN 0 AND 5
    GROUP BY game_id, pid, t0
),
used AS (
    SELECT r.game_id, r.pid, r.t0, group_concat(DISTINCT o.item) AS used, min(o.t) AS use_t
    FROM res r JOIN ev_regen_obs o ON o.game_id = r.game_id AND o.pid = r.pid AND o.state = 'start'
        AND o.t >= r.t0 AND o.t <= coalesce(r.t1, r.t0 + 300)
    GROUP BY r.game_id, r.pid, r.t0
),
win AS (
    SELECT r.game_id, r.pid, r.t0, count(*) AS win, sum(w."used" <> '-') AS win_used
    FROM res r JOIN ev_regen_win w ON w.game_id = r.game_id AND w.pid = r.pid
        AND w.t >= r.t0 AND w.t <= coalesce(r.t1, r.t0 + 300) AND w."under" = 0
        AND ((w.tg > 0 AND w.missmax >= w.tge AND w.tree >= 0 AND w.tree <= 600) OR (w.sv > 0 AND w.missmax >= w.sve))
    GROUP BY r.game_id, r.pid, r.t0
),
sn AS MATERIALIZED (
    SELECT s.game_id, s.pid, CAST(round(s.t) AS INTEGER) AS sec, max(s.hit) AS hit, max(s.hpm) AS hpm
    FROM ev_snap s JOIN gm USING (game_id)
    WHERE s.t >= -1 AND s.t <= coalesce(:until, 600) + 300
    GROUP BY s.game_id, s.pid, CAST(round(s.t) AS INTEGER)
),
rv AS (
    SELECT gm.game_id, coalesce((SELECT max(w.tge) FROM ev_regen_win w WHERE w.game_id = gm.game_id), 112) AS tge,
        coalesce((SELECT max(w.sve) FROM ev_regen_win w WHERE w.game_id = gm.game_id), 390) AS sve
    FROM gm
),
gate AS (
    SELECT r.game_id, r.pid, r.t0, min(h.sec) AS gate
    FROM res r JOIN held d ON d.game_id = r.game_id AND d.pid = r.pid AND d.t0 = r.t0
    JOIN rv ON rv.game_id = r.game_id
    JOIN hs h ON h.game_id = r.game_id AND h.pid = r.pid AND h.sec >= r.t0 AND h.sec < coalesce(r.t1, r.t0 + 300) AND h.live
    JOIN sn n ON n.game_id = h.game_id AND n.pid = h.pid AND n.sec = h.sec
    WHERE ((d.tg > 0 AND n.hpm * (100 - h.hp) / 100.0 >= rv.tge) OR (d.sv > 0 AND n.hpm * (100 - h.hp) / 100.0 >= rv.sve))
        AND NOT EXISTS (SELECT 1 FROM sn k WHERE k.game_id = h.game_id AND k.pid = h.pid AND k.sec BETWEEN h.sec - 2 AND h.sec
            AND k.hit = 1)
    GROUP BY r.game_id, r.pid, r.t0
)
SELECT gm.file, gm.game, r.pid, r.team, r.pos, r.hero, r.t0, r.hp0, r.t1, r.t1 - r.t0 AS secs, r.res, r.back,
    coalesce(r.back, coalesce(:until, 600) + 300) - r.t0 - (SELECT count(*) FROM hs b WHERE b.game_id = r.game_id AND b.pid = r.pid
        AND b.sec >= r.t0 AND b.sec < coalesce(r.back, coalesce(:until, 600) + 300) AND b.live AND b.lane = b.own) AS off_s,
    coalesce(h.tg, 0) AS tg, coalesce(h.sv, 0) AS sv, coalesce(h.cl, 0) AS cl, coalesce(h.ff, 0) AS ff,
    coalesce(u.used, '-') AS used,
    CASE WHEN (coalesce(h.tg, 0) > 0 OR coalesce(h.sv, 0) > 0)
        AND coalesce(u.used, '') NOT LIKE '%tango%' AND coalesce(u.used, '') NOT LIKE '%salve%' THEN 1 ELSE 0 END AS unused,
    coalesce(w.win, 0) AS win, coalesce(w.win_used, 0) AS win_used, u.use_t, gt.gate
FROM res r JOIN gm USING (game_id)
LEFT JOIN gate gt ON gt.game_id = r.game_id AND gt.pid = r.pid AND gt.t0 = r.t0
LEFT JOIN win w ON w.game_id = r.game_id AND w.pid = r.pid AND w.t0 = r.t0
LEFT JOIN held h ON h.game_id = r.game_id AND h.pid = r.pid AND h.t0 = r.t0
LEFT JOIN used u ON u.game_id = r.game_id AND u.pid = r.pid AND u.t0 = r.t0
ORDER BY gm.file, gm.game, r.t0, r.pid
