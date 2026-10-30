-- One row per ev=stack line with the cause of an attempt that did not stack (slice 4, KR S.2a; the only copy of the rule since
-- slice retire-stacks moved dynamic.js stackCause and leftInBox here; read through queries/stack_rows.sql by stackAttempts).
-- cause: a failed attempt's why (NULL when why is ? or absent); a not_stacked attempt with a :59.5 sample (box59 not NULL):
-- bot-in-box (bot59 = 1), camp-in-box (box59 > 0), unseen (box not seen at :59.5, vis59 <> 1, and after is NULL), else no-spawn;
-- NULL otherwise. A non-numeric box59 or vis59 (say n/a) compares as text.
-- left59: the camp neutrals still in the bare box at :59.5, from n59 ("name:dist:in|out:a|-") as name:a|- for each "in" entry,
-- '-' when none, NULL without n59 or when it is '?'.
-- death_flag: 1 when death=1, else 0 (stacks.js prints false on a skip line, which carries no death field; death itself stays NULL there).
-- needs: ev_stack(pid, min, res, why, camp, type, box59, bot59, vis59, after, n59, death, idle)
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
