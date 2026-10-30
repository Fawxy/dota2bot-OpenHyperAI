-- Fragment (`-- include: lane_label`): the CTE `lab` labels every row of a CTE `pts(kind, k, seq, t, x, y)` the including query
-- defines first, as dynamic.js `laneLabel`: base within 1800 of an ancient or 1200 of a fountain, else the lane of the nearest
-- polyline segment within 1100 (ties to the lower seg, the order `POLY` is scanned in), else 'other'. Ends with a comma.
-- Constants (dynamic.js `C.BASE_R`, `C.FOUNTAIN_R`, `C.LANE_R`, `ANCIENT`, `FOUNTAIN`) are pinned by test/lasthit_cause.test.js and
-- test/dynamic.test.js.
lab AS (
    SELECT p.kind, p.k, p.seq, p.t,
        CASE
            WHEN sqrt((p.x + 5920) * (p.x + 5920) + (p.y + 5352) * (p.y + 5352)) < 1800
              OR sqrt((p.x - 5528) * (p.x - 5528) + (p.y - 5000) * (p.y - 5000)) < 1800
              OR sqrt((p.x + 6850) * (p.x + 6850) + (p.y + 6461) * (p.y + 6461)) < 1200
              OR sqrt((p.x - 7020) * (p.x - 7020) + (p.y - 6345) * (p.y - 6345)) < 1200 THEN 'base'
            ELSE coalesce((
                SELECT q.lane FROM (
                    SELECT g.lane, g.seg,
                        sqrt((p.x - (g.x1 + g.f * g.dx)) * (p.x - (g.x1 + g.f * g.dx)) + (p.y - (g.y1 + g.f * g.dy)) * (p.y - (g.y1 + g.f * g.dy))) AS d
                    FROM (
                        SELECT s.*, max(0.0, min(1.0, ((p.x - s.x1) * s.dx + (p.y - s.y1) * s.dy) / s.l2)) AS f FROM lane_segments s
                    ) g
                ) q
                WHERE q.d < 1100 ORDER BY q.d, q.seg LIMIT 1), 'other')
        END AS lane
    FROM pts p
),
