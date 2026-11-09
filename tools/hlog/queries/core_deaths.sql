-- Every death of a lineup core (pos 1-3) before :until (default 600), with a cause (slice core-in-lane, L.3c). The deaths count rises only
-- at the first snap after the respawn, and a killed hero logs snaps before it that are not its last living moment (hp 0 where it fell,
-- or at its fountain): a death is the last snap with hp above 0 before that run (t is that snap; fragment core_death has the rules); the cause reads the core's snaps and ev=trade in the 10 s before it, first match wins:
--   trade     a trade of ours was running or ended within 10 s (ev=trade taken)
--   cut       laning held the 0.9 last-hit desire after a retreat in those 10 s (the cut the slice stops)
--   retreat   it was retreating at the last snap
--   tower     the last snap was within 900 of an enemy tower (positions below)
--   lane      laning mode at the last snap
--   <mode>    any other mode at the last snap (out of our context)
-- Also: hp at the last alive snap, mode, activity, and whether an enemy hero was within attack range + 100 (in_range).
-- Params: like, until; pos_lo, pos_hi the lineup positions (default 1-3; 4-5 reads the supports, slice support-spot).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: core_death
r AS (SELECT gm.file, cd.team, cd.pos, cd.pid, cd.t, cd.hp, cd.mode, cd.activity, cd.in_range, cd.cause FROM cd JOIN gm ON gm.game_id = cd.game_id)
SELECT * FROM r ORDER BY file, t
