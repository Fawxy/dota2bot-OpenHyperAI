-- One row per lane creep and neutral that died, from the death events the log has (scene-and-unit-lives proposal s4, reader
-- first). src is 'log' (a recorded game's replay will fill 'replay').
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
-- ensure: ev_wave_creep_death(team, kind, x, y, by, cid, lane, born)
-- ensure: ev_own_creep_death(team, kind, x, y, by, cid)
-- ensure: ev_creep_death(team, kind, x, y, by, tw, cid)
-- ensure: ev_neutral_death(team, kind, x, y, by, camp)
WITH ul_wave AS NOT MATERIALIZED (SELECT * FROM ev_wave_creep_death),
ul_own AS NOT MATERIALIZED (SELECT * FROM ev_own_creep_death),
ul_enemy AS NOT MATERIALIZED (SELECT * FROM ev_creep_death),
ul_neu AS NOT MATERIALIZED (SELECT * FROM ev_neutral_death),
-- include: unit_life_rows
SELECT * FROM unit_life_rows
