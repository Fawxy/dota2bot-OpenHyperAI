-- What each lineup hero was doing, one row per ev=snap (about one per second), to 12:00 (slice lane-activity).
-- activity, first match wins: hero (attack target is a hero), building, neutral, creep (a lane creep or siege), retreat (mode), lane (laning
-- mode with no recognised target), other (any other mode with no recognised target; a summon as target reads as no target).
-- A target outranks the mode, so a swing during retreat reads as the swing.
-- spike: laning at desire 0.85 or more, the last-hit desire of mode_laning_generic GetDesire.
-- What it could do (builds from slice lane-activity on; NULL before): ol, od reachable last hits and denies on offer; ar attack
-- range; ed nearest visible enemy hero within 1,200, NULL if none; hit by a hero in the last second.
-- in_range: an enemy hero within attack range + 100. A hero's lane is not here: join lane_segments when a question needs it.
-- needs: ev_snap(pid, x, y, alive, hp, mode, d, tgt, lh, dn, deaths, ol, od, ar, ed, hit)
SELECT s.game_id, s.seq, s.t, s.pid, l.team, l.pos, s.x, s.y, s.hp, s.mode, s.d, s.tgt, s.lh, s.dn, s.deaths,
    CASE WHEN s.tgt LIKE '%hero%' THEN 'hero'
         WHEN s.tgt LIKE '%tower%' OR s.tgt LIKE '%rax%' OR s.tgt LIKE '%fort%' OR s.tgt LIKE '%healers%' THEN 'building'
         WHEN s.tgt LIKE '%neutral%' THEN 'neutral'
         WHEN s.tgt LIKE '%creep%' OR s.tgt LIKE '%siege%' THEN 'creep'
         WHEN s.mode = 'retreat' THEN 'retreat'
         WHEN s.mode = 'laning' THEN 'lane'
         ELSE 'other' END AS activity,
    (s.mode = 'laning' AND s.d >= 0.85) AS spike,
    s.ol, s.od, s.ar, s.ed, s.hit,
    CASE WHEN s.ed IS NULL OR s.ar IS NULL THEN 0 ELSE s.ed <= s.ar + 100 END AS in_range
FROM ev_snap s JOIN lineup l ON l.game_id = s.game_id AND l.pid = s.pid
WHERE s.t >= 0 AND s.t <= 720 AND s.x IS NOT NULL AND s.alive IS NOT 0
