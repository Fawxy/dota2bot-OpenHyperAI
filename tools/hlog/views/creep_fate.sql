-- Who got each lane creep that died near a hero, both sides, one row per logged death (slice creep-economy, KR L.1).
-- `side` = 'enemy' (an enemy creep that died near the logging team's heroes: ev=creep_death) or 'own' (a creep of the
-- logging team that died near its heroes: ev=own_creep_death). `team` is the logging team; `pid` the hero credited.
-- fate, enemy side: own_lh (an own hero's last hit, pid), enemy_deny (an enemy hero denied it: the other team's own_creep_death
--   with a denier, same kind, within 1 s and 250 units, mutually nearest pair, two passes: each enemy death keeps its nearest own death, then each own death keeps its nearest enemy death; pid = the enemy denier. By=deny, if an enemy GetDenies read ever works, is enemy_deny too),
--   other (tower, creep, a spell the counters do not see, or a death the other team did not log).
-- fate, own side: own_deny (an own hero denied it, pid), lost (anything else: an enemy last hit, tower or creep kill).
-- tw: enemy side only, the creep_death `tw` (one of the logging team's towers was attacking it the frame before; null
-- on builds before the field).
-- Logs from builds before the one that added ev=own_creep_death (406ee95) have no own deaths, so every enemy deny there reads
-- `other`: split mixed sets by build.
-- Enemy denies exist only here: ev=creep_death `by=deny` never fires (an enemy hero's GetDenies reads 0), so those deaths
-- are by=none in the log and are named by the denier's own team log. A creep is in both teams' logs when each had a hero near;
-- count one side of one team per question. Positions are the last frame seen, so a pair can lie a little apart: 250 is wide
-- enough for a frame at 8x and narrow enough that two creeps of one kind in a wave rarely compete.
-- ensure: ev_creep_death(team, kind, x, y, by, tw)
-- ensure: ev_own_creep_death(team, kind, x, y, by)
-- The rule is fragment creep_fate_rows (shared with the timeline, which reads only its own games).
WITH cf_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death),
cf_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death),
-- include: creep_fate_rows
SELECT * FROM creep_fate_rows
