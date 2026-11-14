// The loss ledger (rework step 6, docs/proposals/2026-11-13-rework.md s6): for the games of one or more runs, every death to
// --until and every last hit of the gap at --at assigned to exactly one cause, ours against OHA, summing to the gap.
// Usage: node ledger.js <run> [<run> ...] [--null <run> ...] [--noise [--games 10]] [--at 600] [--until 720]
//                       [--rows deaths|creeps] [--by lane|pos] [--json] [--no-ingest]
//   <run> is a label prefix (h2hskill1 takes h2hskill1_* and, as a separate prefix, h2hskill1r_*: name both halves).
//   --null <runs>  OHA against OHA runs. Each line gains `mirror` (the line in the mirror, both seats' mean) and the gap's
//                  two parts: `we` (ours against the mirror: what we do worse than OHA does against itself) and `they`
//                  (the mirror against OHA: what OHA gains against us that it cannot gain against itself). we + they = gap.
//                  The mirror is a level to read against, not a target: it has more fighting and a different creep pool.
//   --noise        per line, the game-to-game spread of the gap inside cells (lineup and seat, as gate.js; name one build's
//                  runs) and `se`: the standard error of a row of --games games minus a reference row of the same size,
//                  sd * sqrt(2 / games). A line under about two a game behaves as a count; with this many lines one or
//                  two pass two errors by chance, so a slice names its target line before its batch.
//
//   --by lane|pos  the same table once per lane (top, mid, bot, base, other: where the creep died) or per position (the hero's
//                  pos 1-5; a creep's is its lane's core, `none` when no core of the team holds the lane), per game, ours /
//                  OHA, each split's games all counted. Only the lines the split reaches: by lane the creep lines (pool and
//                  its causes), by pos those and the deaths lines; neutral, unattributed and last-hit totals have no lane.
//                  Takes --null (the mirror's rows split the same way); not --noise.
//
// Ours is the seat in the label (`_rad_` Radiant, `_dire_` Dire): the scoped team of a head-to-head, a label only in OHA
// against OHA. A remote job's stub game is skipped (each log's last game is read).
// Deaths (queries/ledger_deaths.sql): every hero, pos 1-5, one cause each; a line's gap is ours minus OHA per game.
// Last hits: the team's last hits at --at (each hero's last snapshot) split by identity into
//   neutral       neutral creeps the team's heroes got (ev=neutral_death `by`)
//   pool          enemy lane creeps either team's heroes saw die (queries/ledger_creeps.sql): spawns are the same for both
//                 teams, so a smaller pool is creeps that died with no hero of either team near
//   <cause>       each pool creep not taken, by ledger_creeps.sql's cause (a loss: its gap is OHA minus ours)
//   unattributed  last hits no death line names (two rises in one frame, a creep outside the logs' range)
// so last hits = neutral + pool - misses + unattributed, and the lines' gaps sum to the last-hit gap.
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');

const QUERIES = path.join(__dirname, 'queries');
const sql = (name) => fs.readFileSync(path.join(QUERIES, `${name}.sql`), 'utf8');
const DEATH_CAUSES = ['tower', 'outnumbered_alone', 'outnumbered', 'duel', 'even_numbers', 'creeps', 'unexplained'];
const MISS_CAUSES = ['denied', 'off_lane', 'core_dead', 'away_base', 'away_lane', 'away_jungle', 'far_in_lane', 'swing_lost', 'held_back_hero', 'held_back_low_hp', 'held_back', 'idle_in_reach'];

function args(argv) {
    const o = { runs: [], null: [], at: 600, until: 720, rows: undefined, json: false, n: 10 };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--null') into = o.null;
        else if (a === '--noise') o.noise = true;
        else if (a === '--games') o.n = Number(argv[++i]);
        else if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--until') o.until = Number(argv[++i]);
        else if (a === '--rows') o.rows = argv[++i];
        else if (a === '--by') o.by = argv[++i];
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

/** The games of the runs: each log's last game, its label and our seat (2 Radiant, 3 Dire). */
function games(store, runs) {
    const out = [];
    for (const run of runs) {
        const rows = store.query(`SELECT g.game_id, g.file, g.label FROM games g
            WHERE g.label LIKE :p ESCAPE '\\' AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file) ORDER BY g.label`,
        { p: `${run.replace(/_/g, '\\_')}\\_%` });
        for (const r of rows) {
            const seat = /_rad_/.test(r.label) ? 2 : /_dire_/.test(r.label) ? 3 : undefined;
            if (seat === undefined) throw new Error(`${r.label}: no _rad_ or _dire_ seat in the label`);
            out.push({ ...r, seat });
        }
    }
    return out;
}

function teamLastHits(store, g, at) {
    const rows = store.query(`SELECT l.team, sum(coalesce((SELECT s.lh FROM ev_snap s WHERE s.game_id = l.game_id AND s.pid = l.pid
            AND s.lh IS NOT NULL AND s.t <= :at ORDER BY s.t DESC, s.seq DESC LIMIT 1), 0)) AS lh
        FROM lineup l WHERE l.game_id = :g GROUP BY l.team`, { g: g.game_id, at });
    return Object.fromEntries(rows.map((r) => [r.team, r.lh]));
}

function neutralHits(store, g, at) {
    if (!store.tables().includes('ev_neutral_death')) return { 2: 0, 3: 0 };
    const rows = store.query(`SELECT n.team, count(*) AS n FROM ev_neutral_death n JOIN lineup l ON l.game_id = n.game_id
            AND CAST(l.pid AS TEXT) = CAST(n."by" AS TEXT) AND l.team = n.team
        WHERE n.game_id = :g AND n.t < :at GROUP BY n.team`, { g: g.game_id, at });
    const out = { 2: 0, 3: 0 };
    for (const r of rows) out[r.team] = r.n;
    return out;
}

/** Per game and side: deaths by cause, last-hit lines. */
function ledger(store, runs, { at = 600, until = 720 } = {}) {
    const gs = games(store, runs);
    const dSql = sql('ledger_deaths');
    const cSql = sql('ledger_creeps');
    const perGame = [];
    const rows = { deaths: [], creeps: [] };
    for (const g of gs) {
        const side = (team) => (team === g.seat ? 'ours' : 'oha');
        const rec = { label: g.label, ours: blank(), oha: blank() };
        const deaths = store.query(dSql, { like: g.file, until, pos_lo: 1, pos_hi: 5 });
        for (const d of deaths) {
            rec[side(d.team)].deaths[d.cause] = (rec[side(d.team)].deaths[d.cause] || 0) + 1;
            rows.deaths.push({ label: g.label, side: side(d.team), ...d });
        }
        const creeps = store.query(cSql, { like: g.file, at });
        for (const c of creeps) {
            const r = rec[side(c.team)];
            r.pool++;
            if (c.src === 'unseen') r.unseen++;
            if (c.cause === 'taken') r.taken++;
            else r.miss[c.cause] = (r.miss[c.cause] || 0) + 1;
            rows.creeps.push({ label: g.label, side: side(c.team), ...c });
        }
        const lh = teamLastHits(store, g, at);
        const nh = neutralHits(store, g, at);
        for (const team of [2, 3]) {
            const r = rec[side(team)];
            r.lh = lh[team] || 0;
            r.neutral = nh[team] || 0;
            r.unattributed = r.lh - r.neutral - r.taken;
        }
        perGame.push(rec);
    }
    return { games: perGame, rows };
}

function blank() { return { deaths: {}, miss: {}, pool: 0, unseen: 0, taken: 0, lh: 0, neutral: 0, unattributed: 0 }; }

/** The ledger's lines: { measure, line, get(side record), sign }; a line's gap is sign * (ours - OHA). */
const LINES = [
    ...DEATH_CAUSES.map((c) => ({ measure: 'deaths', line: c, get: (s) => s.deaths[c] || 0, sign: 1 })),
    { measure: 'deaths', line: 'total', get: (s) => DEATH_CAUSES.reduce((a, c) => a + (s.deaths[c] || 0), 0), sign: 1 },
    { measure: 'last_hits', line: 'neutral', get: (s) => s.neutral, sign: 1 },
    { measure: 'last_hits', line: 'pool', get: (s) => s.pool, sign: 1 },
    ...MISS_CAUSES.map((c) => ({ measure: 'last_hits', line: c, get: (s) => s.miss[c] || 0, sign: -1 })),
    { measure: 'last_hits', line: 'unattributed', get: (s) => s.unattributed, sign: 1 },
    { measure: 'last_hits', line: 'total', get: (s) => s.lh, sign: 1 },
];
const avg = (a) => a.reduce((x, y) => x + y, 0) / (a.length || 1);

/**
 * Lines as per-game means: { measure, line, ours, oha, gap } with gap the line's share of ours minus OHA. With `nul` (the
 * ledger of OHA against OHA) each line adds `mirror` (both seats' mean there) and the gap's parts `we` (ours against the
 * mirror) and `they` (the mirror against OHA).
 */
function summary(result, nul) {
    return LINES.map(({ measure, line, get, sign }) => {
        const ours = avg(result.games.map((g) => get(g.ours)));
        const oha = avg(result.games.map((g) => get(g.oha)));
        const l = { measure, line, ours, oha, gap: sign * (ours - oha) };
        if (nul) {
            l.mirror = avg(nul.games.flatMap((g) => [get(g.ours), get(g.oha)]));
            l.we = sign * (ours - l.mirror);
            l.they = sign * (l.mirror - oha);
        }
        return l;
    });
}

function cellOf(label) {
    const m = label.match(/_([A-Z])_(?:ours_)?(rad|dire)_\d+$/);
    return m ? `${m[1]}_${m[2]}` : label;
}

/**
 * Per line, the spread of the per-game gap inside cells (lineup and seat; a cell of one game adds nothing):
 * { measure, line, gap, sd, se, df }, se being that of a row of `n` games minus a reference row of `n`.
 */
function noise(result, { n = 10 } = {}) {
    const cells = {};
    for (const g of result.games) (cells[cellOf(g.label)] = cells[cellOf(g.label)] || []).push(g);
    const lists = Object.values(cells).filter((l) => l.length > 1);
    const df = lists.reduce((a, l) => a + l.length - 1, 0);
    if (df < 2) throw new Error(`only ${df} degrees of freedom: too few repeated cells`);
    return LINES.map(({ measure, line, get, sign }) => {
        const d = (g) => sign * (get(g.ours) - get(g.oha));
        let ss = 0;
        for (const list of lists) {
            const mu = avg(list.map(d));
            for (const g of list) ss += (d(g) - mu) ** 2;
        }
        const sd = Math.sqrt(ss / df);
        return { measure, line, gap: avg(result.games.map(d)), sd, se: sd * Math.sqrt(2 / n), df };
    });
}

const HEAD = "per game, ours / OHA; gap = the line's share of ours minus OHA (deaths: more is worse; last hits: less is worse)";
const SPLITS = {
    lane: { creeps: (r) => r.lane, deaths: undefined },
    pos: { creeps: (r) => r.pos, deaths: (r) => r.pos },
};

/**
 * The result split by `by` (lane or pos): { value: { games } } with each game's blank record filled from the rows the split reaches,
 * every value having every game (a game with none of a value counts zero). Lines the split cannot reach are not in `lines`.
 */
function split(result, by) {
    const how = SPLITS[by];
    if (!how) throw new Error('--by takes lane or pos');
    const values = new Set();
    const key = (f, r) => { const v = f(r); return v === undefined || v === null ? 'none' : String(v); };
    for (const r of result.rows.creeps) values.add(key(how.creeps, r));
    if (how.deaths) for (const r of result.rows.deaths) values.add(key(how.deaths, r));
    const out = {};
    for (const v of [...values].sort()) {
        const recs = new Map(result.games.map((g) => [g.label, { label: g.label, ours: blank(), oha: blank() }]));
        for (const r of result.rows.creeps) {
            if (key(how.creeps, r) !== v) continue;
            const s = recs.get(r.label)[r.side];
            s.pool++;
            if (r.src === 'unseen') s.unseen++;
            if (r.cause === 'taken') s.taken++;
            else s.miss[r.cause] = (s.miss[r.cause] || 0) + 1;
        }
        if (how.deaths) {
            for (const r of result.rows.deaths) {
                if (key(how.deaths, r) !== v) continue;
                const s = recs.get(r.label)[r.side];
                s.deaths[r.cause] = (s.deaths[r.cause] || 0) + 1;
            }
        }
        out[v] = { games: [...recs.values()] };
    }
    return { values: out, reaches: (l) => (l.measure === 'deaths' ? !!how.deaths : l.line === 'pool' || MISS_CAUSES.includes(l.line)) };
}

function print(lines, n, head) {
    const f = (v) => (Math.round(v * 10) / 10).toFixed(1);
    const cols = Object.keys(lines[0]).filter((k) => k !== 'measure' && k !== 'line' && k !== 'df');
    console.log(`${n} games; ${head}`);
    console.log(`${'measure'.padEnd(10)} ${'line'.padEnd(18)} ${cols.map((c) => c.padStart(7)).join(' ')}`);
    for (const l of lines) console.log(`${l.measure.padEnd(10)} ${l.line.padEnd(18)} ${cols.map((c) => f(l[c]).padStart(7)).join(' ')}`);
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    if (o.by && (o.noise || o.rows)) throw new Error('--by takes neither --noise nor --rows');
    const result = ledger(store, o.runs, o);
    if (o.rows) {
        const rows = result.rows[o.rows];
        if (!rows) throw new Error('--rows takes deaths or creeps');
        console.log(o.json ? JSON.stringify(rows) : rows.map((r) => JSON.stringify(r)).join('\n'));
    } else if (o.noise) {
        const lines = noise(result, o);
        if (o.json) console.log(JSON.stringify({ games: result.games, noise: lines }));
        else print(lines, result.games.length, `${lines[0].df} degrees of freedom; sd = the per-game gap's spread inside lineup-and-seat cells; se = a row of ${o.n} games minus a reference row of ${o.n}`);
    } else {
        const nul = o.null.length ? ledger(store, o.null, o) : undefined;
        if (nul && !nul.games.length) throw new Error(`--null: no games for ${o.null.join(', ')}`);
        if (o.by) {
            const mine = split(result, o.by);
            const theirs = nul ? split(nul, o.by) : undefined;
            const blocks = Object.entries(mine.values).map(([v, r]) => {
                const m = theirs && (theirs.values[v] || { games: nul.games.map((g) => ({ label: g.label, ours: blank(), oha: blank() })) });
                return [v, summary(r, m).filter(mine.reaches)];
            });
            if (o.json) console.log(JSON.stringify({ by: o.by, games: result.games.length, splits: Object.fromEntries(blocks) }));
            else for (const [v, lines] of blocks) {
                console.log(`== ${o.by} ${v}`);
                print(lines, result.games.length, HEAD + (nul ? `; mirror = OHA against OHA (${nul.games.length} games)` : ''));
            }
        } else {
            const lines = summary(result, nul);
            if (o.json) console.log(JSON.stringify({ games: result.games, lines }));
            else print(lines, result.games.length, HEAD
                + (nul ? `; mirror = OHA against OHA (${nul.games.length} games); gap = we (ours against the mirror) + they (the mirror against OHA)` : ''));
        }
    }
}

module.exports = { ledger, summary, noise, games, split, blank, cellOf, LINES, DEATH_CAUSES, MISS_CAUSES };
