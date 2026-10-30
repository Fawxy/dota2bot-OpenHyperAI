-- Fragment (`-- include: hero_death`, after `-- include: hero_second`): the CTE `death(team, t, n)`, as dynamic.js `deathTimes`
-- did: each rise of a hero's deaths counter adds n deaths, dated at the snapshot before when the gap to it is over 2.5 s (the
-- death, not the respawn: bots log no snapshot while dead); a hero whose last snapshot is over 2.5 s before `last` adds one at
-- that snapshot (`C.DEAD_GAP`). Ends with a comma.
inc AS (
    SELECT team, CASE WHEN tp IS NOT NULL AND t - tp > 2.5 THEN tp ELSE t END AS dt,
        CAST(ceil(deaths - coalesce(lag(deaths) OVER (PARTITION BY pid ORDER BY t, seq), 0)) AS INTEGER) AS n
    FROM hs_snap WHERE typeof(deaths) IN ('integer', 'real')
),
lastsnap AS (
    SELECT team, t FROM (SELECT team, t, row_number() OVER (PARTITION BY pid ORDER BY t DESC, seq DESC) AS rn FROM hs_snap)
    WHERE rn = 1 AND (SELECT last FROM hs_last) - t > 2.5
),
death AS (
    SELECT team, dt AS t, n FROM inc WHERE n > 0
    UNION ALL
    SELECT team, t, 1 FROM lastsnap
),
