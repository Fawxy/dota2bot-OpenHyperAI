-- What hurt each hero (tool slice hp-loss): view `hp_loss` summed per game, hero, basis and source, :from to :until
-- (default 0-720). `secs` seconds with a loss, `loss` HP-% points lost in them, `deaths` deaths with that source set.
-- Read `basis`: `api` rows state what damaged the hero, `inferred` rows (sources ending `?`) what stood near enough to.
-- Params: like, from, until, pid.
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file, game FROM games WHERE file LIKE coalesce(:like, '%'))
SELECT gm.file, gm.game, h.pid, h.basis, h.src, sum(NOT h.died) AS secs, sum(h.loss) AS loss, sum(h.died) AS deaths
FROM gm JOIN hp_loss h ON h.game_id = gm.game_id
WHERE h.t >= coalesce(:from, 0) AND h.t <= coalesce(:until, 720) AND (:pid IS NULL OR h.pid = :pid)
GROUP BY gm.game_id, h.pid, h.basis, h.src
ORDER BY gm.file, gm.game, h.pid, loss DESC
