-- Fragment (`-- include: hero_death`, after `-- include: hero_second`): the CTE `death(team, t, n)`, every death of the game's
-- heroes by the shared rule (fragment ep_death), a hero still dead at the log's end included. Ends with a comma.
-- include: ep_death
death AS (SELECT b.team, e.t, e.n FROM ep_death e JOIN hs_bot b ON b.pid = e.pid),
