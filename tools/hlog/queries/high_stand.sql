-- The two-hero stand's situation (slices high-stand, stand-rule; D2 against D1; bot Threat.Stand with two or more heroes in
-- reach, PackHp and PackBurst), found from snapshots (fragment
-- lane_rules), so it runs on games from before the rule: one row per onset (no such second in the 5 before) of a second from
-- 1:30 in which the hero, not in retreat mode, is at 70% HP or more, hit by no hero (`hit` 0), with 2 or more enemy heroes in
-- reach (their attack range + 600), outside an enemy tower's reach (750) and 1,500 of our fountain. The snapshot has no burst,
-- so the rule's "their burst under half our HP" is not tested here (`judgement`: it counts some right leaves as violations,
-- the same for both sides).
--   ret        retreat mode in any of the 3 s after (the violation: D2 stays); ret_nohit: in a second with no hit on us
--   died       killed within 10 s (the opposite rule, D1)
--   even       the enemies in reach are no more than me and the allies within 1,200
-- Params: like, until (default 720).
WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games WHERE file LIKE coalesce(:like, '%')),
-- include: lane_rules
hs_sit AS MATERIALIZED (
    SELECT o.* FROM lr_f o
    WHERE o.sec >= 90 AND o.sec <= coalesce(:until, 720) AND o.hp >= 70 AND o.hit = 0 AND o.en_r >= 2
        AND o.en_tw2 > 750 * 750 AND o.fnt2 > 1500 * 1500 AND coalesce(o.mode, '') <> 'retreat'
),
hs_on AS (
    SELECT s.* FROM hs_sit s
    WHERE NOT EXISTS (SELECT 1 FROM hs_sit z WHERE z.game_id = s.game_id AND z.pid = s.pid AND z.sec >= s.sec - 5 AND z.sec < s.sec)
)
SELECT gm.file, o.side, o.team, o.pos, o.pid, o.sec AS t, o.hp, o.en_r AS en, o.al12 AS al,
    EXISTS (SELECT 1 FROM lr_f z WHERE z.game_id = o.game_id AND z.pid = o.pid AND z.sec BETWEEN o.sec + 1 AND o.sec + 3 AND z.mode = 'retreat') AS ret,
    EXISTS (SELECT 1 FROM lr_f z WHERE z.game_id = o.game_id AND z.pid = o.pid AND z.sec BETWEEN o.sec + 1 AND o.sec + 3 AND z.mode = 'retreat' AND z.hit = 0) AS ret_nohit,
    EXISTS (SELECT 1 FROM lr_death d WHERE d.game_id = o.game_id AND d.pid = o.pid AND d.dsec BETWEEN o.sec AND o.sec + 10) AS died,
    o.en_r <= o.al12 + 1 AS even
FROM hs_on o JOIN gm ON gm.game_id = o.game_id
ORDER BY gm.file, o.sec, o.pid
