-- One row per ev=stack line with the cause slice 4's stackCause derives for an attempt that did not stack
-- (dynamic.js stackAttempts on the slice-4-stack branch; this view is the one place the rule lives once that script retires).
-- Differs from stackCause only where its JS is an artifact, none of which today's ev=stack emitter writes: a failed attempt
-- with why=? or no why gives NULL here ('?' / 'undefined' there), and bot59=true counts as 1 here (a string, so not 1, there).
-- A non-numeric box59 or vis59 (say n/a) compares as text in SQL and as NaN in JS, so the two can disagree on it.
-- needs: ev_stack(pid, min, res, why, camp, type, box59, bot59, vis59, after)
SELECT s.*, g.file, g.game,
    CASE
        WHEN s.res = 'failed' THEN CAST(s.why AS TEXT)
        WHEN s.res = 'not_stacked' AND s.box59 IS NOT NULL THEN
            CASE
                WHEN s.bot59 = 1 THEN 'bot-in-box'
                WHEN s.box59 > 0 THEN 'camp-in-box'
                WHEN (s.vis59 IS NULL OR s.vis59 <> 1) AND s.after IS NULL THEN 'unseen'
                ELSE 'no-spawn'
            END
    END AS cause
FROM ev_stack s JOIN games g USING (game_id)
