-- Fragment (`-- include: ep_exchange`): the one definition of an exchange. Needs what ep_second needs.
-- CTE `ep_exchange(game_id, a, b, t0, t1, a_secs, b_secs)`: two opposing heroes attacking, either or both, a new exchange after
-- more than 5 s with neither attacking the other. a struck first (a tie: the lower pid); a_secs and b_secs are each one's
-- attack seconds on the other, so b_secs 0 is an exchange that was not answered. A two-on-two is up to four exchanges.
-- Ends with a comma.
-- include: ep_attack
epx_h AS (
    SELECT game_id, sec, apid, min(apid, tpid) AS lo, max(apid, tpid) AS hi FROM ep_hit
),
epx_s AS (
    SELECT h.*, CASE WHEN h.sec - lag(h.sec) OVER w <= 5 THEN 0 ELSE 1 END AS brk
    FROM epx_h h WINDOW w AS (PARTITION BY h.game_id, h.lo, h.hi ORDER BY h.sec, h.apid)
),
epx_k AS (
    SELECT e.*, sum(brk) OVER (PARTITION BY game_id, lo, hi ORDER BY sec, apid) AS k FROM epx_s e
),
epx_o AS (
    SELECT e.*, first_value(apid) OVER (PARTITION BY game_id, lo, hi, k ORDER BY sec, apid) AS a FROM epx_k e
),
ep_exchange AS MATERIALIZED (
    SELECT game_id, a, CASE WHEN a = lo THEN hi ELSE lo END AS b, min(sec) AS t0, max(sec) AS t1,
        sum(apid = a) AS a_secs, sum(apid <> a) AS b_secs
    FROM epx_o GROUP BY game_id, lo, hi, k, a
),
