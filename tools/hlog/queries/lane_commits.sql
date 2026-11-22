-- Lane fight commits: one row per game and role from `ev=trade kind=kill` (states/trade's kill), to
-- :until (default 600). offers (every kill line), taken (result kill or done), kills (result kill), lost (offered, never taken by
-- attack mode: the mode that held the hero is in `why`), deaths (the hero's death, fragment ep_death,
-- between the commit's start, its line's t less dur, and 5 s after its line). Per commit: kill_rate = kills / taken,
-- death_rate = deaths / taken. :lf (default: any) reads only the lines with that `lf` (older logs: 1 under the retired lane-fight
-- switches, 0 without; today's builds log none, which reads as 0). :kind `kill` (default) the commits, `join` the joins (today's lane
-- fights from the play roll are joins on their play), `fight` the lane fights of older logs; joins counts the lines with `join=1`
-- (the hero joined another hero's play) and the rest are rolled by the hero itself.
-- Params: like (LIKE pattern on games.file), until, lf, kind.
-- ensure: ev_trade(pid, kind, result, dur, role, lf, join)
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
k AS (
    SELECT tr.game_id, tr.t, tr.pid, tr.role, tr.result, tr.dur, tr."join" AS joined
    FROM ev_trade tr JOIN gm ON gm.game_id = tr.game_id
    WHERE tr.kind = coalesce(:kind, 'kill') AND tr.t < coalesce(:until, 600)
      AND (:lf IS NULL OR coalesce(tr.lf, 0) = :lf)
),
-- include: ep_death
dd AS (SELECT game_id, pid, t FROM ep_death)
SELECT gm.file, coalesce(k.role, 'core') AS role, count(*) AS offers,
    sum(k.result IN ('kill', 'done')) AS taken, sum(k.result = 'kill') AS kills, sum(k.result = 'lost') AS lost,
    sum(k.result IN ('kill', 'done') AND EXISTS (SELECT 1 FROM dd WHERE dd.game_id = k.game_id AND dd.pid = k.pid
        AND dd.t BETWEEN k.t - k.dur - 0.5 AND k.t + 5)) AS deaths,
    coalesce(sum(k.joined = 1), 0) AS joins
FROM k JOIN gm ON gm.game_id = k.game_id
GROUP BY gm.file, coalesce(k.role, 'core') ORDER BY gm.file, role
