-- The three lane polylines as segments (seg = drawing order; top, mid, bot), from the 7.41 tower and ancient positions in
-- dynamic.js (`POLY`; a test keeps the two equal). A point's lane is the nearest segment within 1100 units; see `@lasthit_cores`.
SELECT column1 AS seg, column2 AS lane, column3 AS x1, column4 AS y1, column5 AS x2, column6 AS y2,
    column5 - column3 AS dx, column6 - column4 AS dy,
    1.0 * ((column5 - column3) * (column5 - column3) + (column6 - column4) * (column6 - column4)) AS l2
FROM (VALUES
    (0, 'top', -5920, -5352, -6592, -3408),
    (1, 'top', -6592, -3408, -6501, -872),
    (2, 'top', -6501, -872, -6336, 1856),
    (3, 'top', -6336, 1856, -5275, 6036),
    (4, 'top', -5275, 6036, -128, 6016),
    (5, 'top', -128, 6016, 5528, 5000),
    (6, 'mid', -5920, -5352, -4640, -4144),
    (7, 'mid', -4640, -4144, -3190, -2926),
    (8, 'mid', -3190, -2926, -1544, -1408),
    (9, 'mid', -1544, -1408, 524, 652),
    (10, 'mid', 524, 652, 2496, 2112),
    (11, 'mid', 2496, 2112, 4272, 3759),
    (12, 'mid', 4272, 3759, 3552, 5776),
    (13, 'mid', 3552, 5776, 5528, 5000),
    (14, 'bot', -5920, -5352, -3952, -6112),
    (15, 'bot', -3952, -6112, -360, -6256),
    (16, 'bot', -360, -6256, 4860, -6379),
    (17, 'bot', 4860, -6379, 6269, -2240),
    (18, 'bot', 6269, -2240, 6400, 384),
    (19, 'bot', 6400, 384, 6336, 3032),
    (20, 'bot', 6336, 3032, 5528, 5000)
)
