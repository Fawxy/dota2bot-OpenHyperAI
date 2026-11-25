-- The lane creep offer's shadow lines joined to what happened to each creep (master docs/proposals/2026-11-25-no-creep-unpaid.md s4a):
-- one row per `ev=choice kind=creep` line (one per core hero and lane creep, written when the creep leaves the hero's nearby lists),
-- its answers as the bot logged them, and the creep's death from the line's own team's side (fragment creep_paid_rows). Counted per
-- hero cell by `q @creep_offer_cells`; graded by `q @creep_offer_grades`.
-- The join is the creep's id, a number each team's Lua state hands out (`Telemetry.CreepId`): the line's `cid` against the team's
-- own `unit_seen` cid for a creep of its own (`who=o`), against the cid on the team's `creep_death` row for a creep of theirs
-- (`who=t`). A death counts only when it falls from `back` seconds before the line to `fwd` after it (a creep that left the lists alive and
-- died later is not that line's: `matched` 0). A theirs creep with no `creep_death` of that cid (the row is written only for a
-- death at half health or less within 1,500 of a living hero, and only on logs from 25/11/2026) takes, as `src` `owner`, the owner's
-- death of the same kind within `back` to `fwd` of the line when exactly one such death is free and within 1,500 of the hero's
-- snapshot at the line; else `matched` 0.
-- Columns: file, game, label, lineup, arm, team, pid, hero, pos, t (the line's, the creep's leaving the lists), lane, slot, want, cid, ck, who,
-- wo, wl, walk, due, dies, slk, hpp, mode, crhp, g2, g2r, pc, pd, ptw, eh, exs, en, kb, kt, md, ed, ein, atk, hh, sh, ch, ra, enh (the line's fields, kind=creep; the heights are `GetHeightLevel` of the hero, the stand spot and the creep, enh `pid:level;` in en's order, NULL on logs before the heights),
-- matched (1 when a death is joined), src (cid or owner), dt (death t), how, paid, by_pid (creep_paid_rows's, read from the hero's team),
-- mine (1 when this hero took it: a last hit on theirs, a deny on ours), inrange (walk = 0), outdmg (ein > 0 and ed > md), covered
-- (eh > 0), up (1 when the stand spot is lower than the creep, 0 when level or above, NULL without heights), proj (1 when the hero's attack range ra is above 320, where the engine reads a projectile: engine/src/lasthit.ts RANGED_ABOVE), snap (the time of the answers: slot + wo for want 1, NULL for want 0).
-- Params: like (a path fragment or run label) or batch (the exact run name), one is required; from, until (default 0 and 600; the
-- line's t); back, fwd (default 1 and 1); each a comma list, unset for all: ck (m, r, s, f), who (t, o), pid, hero.
-- A few seconds a game.
WITH gm AS MATERIALIZED (SELECT game_id, file, game, label FROM games
    WHERE bots > 0 AND (file LIKE coalesce(:like, '') OR run_label_part(label, 'batch') = :batch)),
-- include: creep_offer_rows
SELECT gm.file, gm.game, gm.label, r.lineup, r.arm, o.team, o.pid, o.hero, o.pos, o.t, o.lane, o.slot, o.want, o.cid, o.ck, o.who,
    o.wo, o.wl, o.walk, o.due, o.dies, o.slk, o.hpp, o.mode, o.crhp, o.g2, o.g2r, o.pc, o.pd, o.ptw, o.eh, o.exs, o.en,
    o.kb, o.kt, o.md, o.ed, o.ein, o.atk, o.hh, o.sh, o.ch, o.ra, o.enh, o.matched, o.src, o.dt, o.how, o.paid, o.by_pid, o.mine, o.inrange, o.outdmg, o.covered, o.up, o.proj, o.snap
FROM creep_offer_rows o JOIN gm USING (game_id)
LEFT JOIN run_label r USING (game_id)
ORDER BY gm.file, gm.game, o.t, o.pid, o.cid
