-- One row per ended job (ev=job phase=end; slice job-chooser): what ended it, sorted for the bars.
-- class: oha-gated (an OHA mode outside the chooser's exceptions list, or OHA farm's run and defend-ping aborts), exception (on
-- the list: retreat, assemble, attack for the 9 heroes OHA overrides), valve (Valve's own modes), other (the job's own end,
-- the switch-off hit cancel, and the unnamed mode_26 and mode_28).
-- Sort from the slice file, "Mode sort for job_ends". Outpost is gated too, but BotMode has no number for it, so it reads other.
-- needs: ev_job(pid, job, phase, why, host, hit)
-- ensure: ev_bot(pid, hero)
-- ensure: ev_player(pid, hero)
WITH e AS (
    SELECT j.*, CASE WHEN CAST(j.why AS TEXT) LIKE 'preempted:mode=%' THEN CAST(substr(j.why, 16) AS INTEGER) END AS mode
    FROM ev_job j WHERE j.phase = 'end'
)
SELECT e.game_id, g.file, g.game, e.t, e.pid, e.job, e.why, e.mode, coalesce(e.hit, 0) AS hit, n.hero,
    CASE
        WHEN e.why IN ('cancelled:run', 'cancelled:defend-ping') THEN 'oha-gated'
        WHEN e.why = 'cancelled:retreat' THEN 'exception'
        WHEN e.mode IN (1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 20, 22) THEN 'oha-gated'
        WHEN e.mode IN (4, 14) THEN 'exception'
        WHEN e.mode = 2 AND n.hero IN ('muerta', 'marci', 'primal_beast', 'dark_willow', 'elder_titan', 'hoodwink', 'wisp', 'kez') THEN 'exception'
        WHEN e.mode IN (2, 18, 19, 21) THEN 'valve'
        ELSE 'other'
    END AS class
FROM e JOIN games g USING (game_id)
LEFT JOIN (
    SELECT game_id, pid, hero FROM (
        SELECT game_id, pid, hero, row_number() OVER (PARTITION BY game_id, pid ORDER BY seq DESC) AS rn
        FROM (SELECT game_id, seq, pid, hero FROM ev_bot UNION ALL SELECT game_id, seq, pid, hero FROM ev_player)
    ) WHERE rn = 1
) n ON n.game_id = e.game_id AND n.pid = e.pid
