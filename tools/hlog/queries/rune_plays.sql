-- Plays (slice rune-spawn, library hum/plays): one row per kind.
--   chances   `ev=play` lines; fired (fire=1); zero_* hard zeros and no-rng; w the mean weight of non-zero chances
--   ended     `ev=play_end` lines of fired plays; kill, forced, none, died, trade by `res`; contested (a shrine contest
--             channelled); timeout (why=timeout); joins (sum of `join`); unended fired plays with no end line
-- Params: like.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE file LIKE coalesce(:like, '%')),
c AS (SELECT p.* FROM ev_play p JOIN gm ON gm.game_id = p.game_id),
e AS (SELECT p.* FROM ev_play_end p JOIN gm ON gm.game_id = p.game_id)
SELECT c.kind,
    count(*) AS chances, total(c.fire = 1) AS fired,
    total(c.zero = 'hp') AS zero_hp, total(c.zero = 'outnumbered') AS zero_outn, total(c.zero = 'tower') AS zero_tower,
    total(c.zero = 'no-rng') AS no_rng, round(avg(CASE WHEN c.w > 0 THEN c.w END), 2) AS w,
    (SELECT count(*) FROM e WHERE e.kind = c.kind) AS ended,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'kill') AS kill,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'forced') AS forced,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'none') AS none,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'died') AS died,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'trade') AS trade,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.res = 'contested') AS contested,
    (SELECT count(*) FROM e WHERE e.kind = c.kind AND e.why = 'timeout') AS timeout,
    (SELECT coalesce(sum(e."join"), 0) FROM e WHERE e.kind = c.kind) AS joins,
    total(c.fire = 1 AND NOT EXISTS (SELECT 1 FROM e WHERE e.game_id = c.game_id AND e.id = c.id AND e.pid = c.pid)) AS unended
FROM c
GROUP BY c.kind
ORDER BY c.kind;
