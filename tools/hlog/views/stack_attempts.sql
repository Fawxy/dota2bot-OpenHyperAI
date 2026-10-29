-- One row per ev=stack line with the cause slice 4's stackCause derives for an attempt that did not stack
-- (dynamic.js stackAttempts on the slice-4-stack branch; this view is the one place the rule lives once that script retires).
-- Differs from stackCause only where its JS is an artifact, none of which today's ev=stack emitter writes: a failed attempt
-- with why=? or no why gives NULL here ('?' / 'undefined' there), and bot59=true counts as 1 here (a string, so not 1, there).
-- A non-numeric box59 or vis59 (say n/a) compares as text in SQL and as NaN in JS, so the two can disagree on it.
-- left59: dynamic.js leftInBox(n59): the heroes still in the box at :59 as pid:distance, '-' when none, NULL without n59 or when it is '?'.
-- death_flag: 1 when death=1, else 0 (stacks.js prints false on a skip line, which carries no death field; death itself stays NULL there).
-- needs: ev_stack(pid, min, res, why, camp, type, box59, bot59, vis59, after, n59, death)
SELECT s.*, g.file, g.game,
    coalesce(s.death = 1, 0) AS death_flag,
    CASE WHEN s.n59 IS NULL OR s.n59 = '?' THEN NULL ELSE coalesce((
        WITH RECURSIVE sp(rest, tok) AS (
            SELECT s.n59 || ',', NULL
            UNION ALL
            SELECT substr(rest, instr(rest, ',') + 1), substr(rest, 1, instr(rest, ',') - 1) FROM sp WHERE rest <> ''
        )
        SELECT group_concat(substr(tok, 1, instr(tok, ':') - 1) || ':' || substr(tok, length(rtrim(tok, replace(tok, ':', ''))) + 1), ',')
        FROM sp WHERE tok LIKE '%:in:%'), '-') END AS left59,
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
