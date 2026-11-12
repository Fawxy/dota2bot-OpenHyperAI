// The loss ledger (rework step 6, docs/proposals/2026-11-13-rework.md s6): for the games of one or more runs, every death to
// --until and every last hit of the gap at --at assigned to exactly one cause, ours against OHA, summing to the gap.
// Usage: node ledger.js <run> [<run> ...] [--at 600] [--until 720] [--rows deaths|creeps] [--json] [--no-ingest]
//   <run> is a label prefix (h2hskill1 takes h2hskill1_* and, as a separate prefix, h2hskill1r_*: name both halves).
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
    const o = { runs: [], at: 600, until: 720, rows: undefined, json: false };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--until') o.until = Number(argv[++i]);
        else if (a === '--rows') o.rows = argv[++i];
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else o.runs.push(a);
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

/** Lines as per-game means: { measure, line, ours, oha, gap } with gap the line's share of ours minus OHA. */
function summary(result) {
    const n = result.games.length || 1;
    const mean = (f) => ['ours', 'oha'].map((s) => result.games.reduce((a, g) => a + f(g[s]), 0) / n);
    const out = [];
    const push = (measure, line, [o, h], sign = 1) => out.push({ measure, line, ours: o, oha: h, gap: sign * (o - h) });
    let dTotal = [0, 0];
    for (const c of DEATH_CAUSES) {
        const v = mean((s) => s.deaths[c] || 0);
        dTotal = [dTotal[0] + v[0], dTotal[1] + v[1]];
        push('deaths', c, v);
    }
    push('deaths', 'total', dTotal);
    push('last_hits', 'neutral', mean((s) => s.neutral));
    push('last_hits', 'pool', mean((s) => s.pool));
    for (const c of MISS_CAUSES) push('last_hits', c, mean((s) => s.miss[c] || 0), -1);
    push('last_hits', 'unattributed', mean((s) => s.unattributed));
    push('last_hits', 'total', mean((s) => s.lh));
    return out;
}

function print(lines, n) {
    const f = (v) => (Math.round(v * 10) / 10).toFixed(1);
    console.log(`${n} games; per game, ours / OHA; gap = the line's share of ours minus OHA (deaths: more is worse; last hits: less is worse)`);
    console.log(`${'measure'.padEnd(10)} ${'line'.padEnd(18)} ${'ours'.padStart(7)} ${'oha'.padStart(7)} ${'gap'.padStart(7)}`);
    for (const l of lines) console.log(`${l.measure.padEnd(10)} ${l.line.padEnd(18)} ${f(l.ours).padStart(7)} ${f(l.oha).padStart(7)} ${f(l.gap).padStart(7)}`);
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const result = ledger(store, o.runs, o);
    if (o.rows) {
        const rows = result.rows[o.rows];
        if (!rows) throw new Error('--rows takes deaths or creeps');
        console.log(o.json ? JSON.stringify(rows) : rows.map((r) => JSON.stringify(r)).join('\n'));
    } else if (o.json) {
        console.log(JSON.stringify({ games: result.games, lines: summary(result) }));
    } else {
        print(summary(result), result.games.length);
    }
}

module.exports = { ledger, summary, games, DEATH_CAUSES, MISS_CAUSES };
