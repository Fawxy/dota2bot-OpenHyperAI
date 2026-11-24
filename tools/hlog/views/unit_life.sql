-- One row per lane creep and neutral, from the death events the log has (a game with ev=unit_seen: from unit_seen and unit_gone, a
-- row per unit seen, t1 NULL while it was not found dead by 12:00; see the fragment's header) (scene-and-unit-lives proposal s4, reader
-- first). src is 'log', or 'replay' for a game `hlog.js replay` has read (below).
--   uid      lane creep: its owning team and that team's cid, `2:412`; a creep with no cid (builds before the field) `2:e<seq>`
--            (the owner's death line); a creep only the other team saw `2:x<observer cid>` (the observer numbers its own
--            sightings, so it is never the owner's cid; `2:xe<seq>` with no cid). Neutral: `n2:<seq>`, the seq of the
--            Radiant sighting's line when both teams saw it (ev=neutral_death has no cid), else of the one line.
--   kind     lane | neutral. team: the lane creep's owner; 4 for a neutral. type: melee, ranged or siege (the event's kind);
--            NULL for a neutral (its name is not logged).
--   lane     a lane creep's top|mid|bot: ev=wave_creep_death's own, else the lane of its death spot (fragment lane_label: top,
--            mid, bot, base or other). NULL for a neutral. camp: a neutral's camp index (ev=neutral_death camp, NULL out of
--            camp range); NULL for a lane creep.
--   wave     floor(born / 30), a creep in ev=wave_creep_death (from team-bots c87cd648, near or far from any hero), else NULL.
--   t0       that `born`: the first frame the owner saw it. x0, y0 are NULL (nothing logs the first spot); t0 NULL for a
--            neutral and for a creep no wave_creep_death names.
--   t1 x1 y1 where and when it was last seen alive: the owner's line when the owner logged it, else the other team's.
--   by_kind  hero (an enemy of the owner took it, by_pid) | deny (an owner hero, by_pid; by_pid NULL when only the other
--            team's `by=deny` says so) | tower (nothing above, and one of the taker's towers hit it the frame before: `tw`,
--            not surely the killer) | unknown. A creep or neutral kill reads unknown (no log names it). A neutral: hero or
--            unknown, by the pid of the line naming one.
--   by_src   where the killer was read: own (the owner's line: a deny), taker (the taker's team, whose log is the only one
--            with the unit), paired (the taker's line paired to the owner's), NULL with by_kind unknown. A neutral's
--            `paired` is the Dire sighting's pid on a row whose spot is the Radiant sighting's.
-- An enemy hero's last hit or deny of a creep is in no owner line: the owner's `by` only ever names its own heroes (checked on
-- the 36 games with ev=wave_creep_death: all 1,366 pids are the owner's), and the other team's GetDenies reads 0, so the
-- taker comes only from the taker's team's ev=creep_death by pairing: same kind, within 1 s and 250 units, mutually nearest
-- (one pass, as fragment wave_fate has always paired). A game's owner rows are ev=wave_creep_death plus any
-- ev=own_creep_death line it has no cid in (a build without the wave event has only the second).
-- A neutral's two sightings (team 2 and team 3) are one unit when within 1 s and 250 units, mutually nearest, and at most one
-- names a hero: two heroes taking neutrals at once are two units. Not in today's events (NULL): x0, y0, t0 of a neutral and of
-- a creep outside the wave event, a neutral's name, `flag` as a type.
-- A creep_death line (the other team's sighting) is written when a creep at low health leaves the writer's unit list
-- (trackCreepDeaths, telemetry.ts), which can be a creep that went into fog and lived: ev=creep_revive is written if it reappears,
-- with no cid. So a row with by_src = taker whose uid has `:x` (no owner line) is a sighting, not a confirmed death; a paired
-- row is confirmed by the owner's own line.
-- Store-wide it pairs every game: read one game or a few with query unit_life (--p game=N or like=), whose inputs are only those
-- games'. The rules are fragment unit_life_rows.
-- A game with replay rows (rp_game, from `hlog.js replay <dem>`; replay.js): its rows are the replay's whole, none of the log's, none paired:
-- uid `<entity>.<n>` (entity indices are reused), lane from where the creep was 20 s after it spawned, wave floor(t0 / 30), camp the nearest
-- camp_boxes.json camp within 700 of a neutral's first spot, type melee, ranged, siege, flag or a neutral's name, t0 x0 y0 the first live
-- frame, t1 x1 y1 its death (NULL alive at 12:00 and despawned), by_kind also creep and neutral (a summon of a hero reads unknown), by_pid
-- a hero or denier, by_src replay (replay_amb: two like units died within 0.1 s with different killers, so the killers may be swapped), src
-- replay. The same units from the log: CTE unit_life_log of the fragment; @unit_grade grades them against the replay's.
-- A game with ev=unit_seen (team-bots after 836e2a2d): a row per own lane creep, from the owner's unit_seen (t0 = born to 0.1 s, x0, y0,
-- lane, type: melee, ranged, siege or flag) and unit_gone (t1, x1, y1; no row of a creep still alive at 12:00 has them), `uid` its team and
-- cid. The enemy hero's last hit and a tower's are not readable from the owner's side, so the other team's creep_death is still paired
-- for them (by_src paired). A creep only the enemy saw is no row there. A neutral: `type` its unit name, `camp` and t0 x0 y0 from
-- its unit_seen; the two teams' sightings are one unit when their unit_gone rows are within 1 s and 250 units (uid the Radiant
-- sighting's, `n2:<cid>`); a neutral never found dead is a row per team (t1 NULL); a neutral out of sight and back is one unit.
-- `hid` (last column; NULL for a lane creep and for a game read from the old events): 1 on a neutral found dead only after it had left
-- the unit list, whose t1 is when that was noticed (up to 0.5 s and a frame after its death), spot the last one seen (it may have been
-- pulled or moved since) and no taker. Two exact rows (hid 0) pair when of the same type, within 1 s and 250 units, mutually nearest;
-- a row with hid 1 pairs with the other team's row of the same type and camp within 2 s, mutually nearest by time, at any distance
-- (the exact partner's t1, x1, y1 and hid 0 are kept); a neutral in no camp is never merged by time alone, so it can count twice.
-- A neutral never found dead (t1 NULL) is one row per team: count dead neutrals as rows with t1 not NULL, never all rows.
-- A lane creep that was listed again after leaving (a change of owner) keeps its first unit_gone: t1 is its first exit, not a later death.
-- `cd_seq cd_t cd_x cd_y tw` (after hid; NULL for a neutral and a replay row): the other team's ev=creep_death line the creep paired to, or, on a
-- row for a creep only the taker saw, that line: its seq, t, spot and `tw`. `seq`: the owner's closing line (wave_creep_death, else own_creep_death, else
-- unit_gone; its unit_seen for a creep still alive; NULL on a taker-only row). They let a reader that keys on a creep_death line's seq (view creep_fate
-- and its joiners) find the unit, and see the sighting's own time and spot, which differ from t1 x1 y1 by up to 1 s and 250 units.
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
-- ensure: ev_unit_seen(team, cid, kind, type, lane, camp, x, y)
-- ensure: ev_unit_gone(team, cid, x, y, hp, by, hid)
WITH ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death),
ul_useen AS NOT MATERIALIZED (SELECT * FROM ev_unit_seen),
ul_ugone AS NOT MATERIALIZED (SELECT * FROM ev_unit_gone),
ul_rp AS NOT MATERIALIZED (SELECT * FROM rp_unit),
-- include: unit_life_rows
SELECT * FROM unit_life_rows
