// Kill chances per side (ROADMAP row 1, the `kill-chances` proposal (master tag `pre-process-v5`)): queries/kill_chances.sql for the games of
// one or more runs, read per game for each hunting side: `ours` the chances our heroes have (an OHA hero low), `oha` OHA's
// against us. Ours is the seat in the label, as ledger.js.
// Usage: node kill_chances.js <run> [<run> ...] [--null <run> ...] [--until 720] [--rows] [--json] [--no-ingest]
//   --null <runs>  OHA against OHA runs: a `mirror` column, both seats' mean per game
//   --rows         the hunter rows as JSON lines (label, side added), not the table
// Lines, per game:
//   chances        chances (the query's header has the definitions)
//   attacked       the share of chances some hunting-side hero attacked within 8 s;  two+  chances attacked by two or more
//   died           chances where the low hero died within 12 s, and their share
//   hunters <grp>  hunter-chances of side cores (pos 1, 3), the mid (2) or the supports (4, 5), and the share that attacked;
//                  `idle in` the commonest modes of those that did not, share of the group's hunter-chances
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { games } = require('./ledger');

const SQL = fs.readFileSync(path.join(__dirname, 'queries', 'kill_chances.sql'), 'utf8');
const GROUPS = { cores: [1, 3], mid: [2], supports: [4, 5] };

function args(argv) {
    const o = { runs: [], null: [], until: 720 };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--null') into = o.null;
        else if (a === '--until') o.until = Number(argv[++i]);
        else if (a === '--rows') o.rows = true;
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

/** The hunter rows of the runs' games, each with label and side (the hunting team's: ours when it is the label's seat). */
function rows(store, runs, { until = 720 } = {}) {
    const gs = games(store, runs);
    const out = [];
    for (const g of gs) {
        for (const r of store.query(SQL, { like: g.file, until, pos_lo: 1, pos_hi: 5 })) {
            out.push({ label: g.label, side: 5 - r.team === g.seat ? 'ours' : 'oha', ...r });
        }
    }
    return { games: gs, rows: out };
}

/** Per-game lines for one side's rows over n games: { chances, attacked, two, died, groups: { name: { n, atk, modes } } }. */
function tally(rs, n) {
    const ch = new Map();
    for (const r of rs) ch.set(`${r.label}|${r.pid}|${r.t}`, r);
    const cs = [...ch.values()];
    const out = {
        chances: cs.length / n,
        attacked: share(cs.filter((c) => c.attackers > 0).length, cs.length),
        two: cs.filter((c) => c.attackers >= 2).length / n,
        died: cs.filter((c) => c.died).length / n,
        diedShare: share(cs.filter((c) => c.died).length, cs.length),
        groups: {},
    };
    for (const [name, pos] of Object.entries(GROUPS)) {
        const hs = rs.filter((r) => pos.includes(r.hpos));
        const idle = {};
        for (const h of hs) if (!h.hatk) idle[h.hmode || 'none'] = (idle[h.hmode || 'none'] || 0) + 1;
        const modes = Object.entries(idle).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([m, k]) => [m, share(k, hs.length)]);
        out.groups[name] = { n: hs.length / n, atk: share(hs.filter((h) => h.hatk).length, hs.length), modes };
    }
    return out;
}

const share = (a, b) => (b ? a / b : NaN);

/** The table's columns: ours, oha and, with a mirror, both of its seats over twice its games. */
function summary(result, nul) {
    const n = result.games.length;
    const cols = {
        ours: tally(result.rows.filter((r) => r.side === 'ours'), n),
        oha: tally(result.rows.filter((r) => r.side === 'oha'), n),
    };
    if (nul) cols.mirror = tally(nul.rows, 2 * nul.games.length);
    return cols;
}

function print(cols, n, nm) {
    const names = Object.keys(cols);
    const pct = (v) => (Number.isNaN(v) ? '-' : `${Math.round(100 * v)}%`);
    const num = (v) => v.toFixed(1);
    const line = (label, f) => console.log(`${label.padEnd(18)} ${names.map((c) => f(cols[c]).padStart(18)).join('')}`);
    console.log(`per game: ours (our heroes hunting) / oha (OHA hunting us)${nm ? ` / mirror (${nm} games, per seat)` : ''}; ${n} games`);
    line('', (c) => names.find((k) => cols[k] === c));
    line('chances', (c) => num(c.chances));
    line('attacked in 8 s', (c) => pct(c.attacked));
    line('two+ attacked', (c) => num(c.two));
    line('died in 12 s', (c) => `${num(c.died)} (${pct(c.diedShare)})`);
    for (const g of Object.keys(GROUPS)) {
        line(`hunters ${g}`, (c) => `${num(c.groups[g].n)}, ${pct(c.groups[g].atk)}`);
        for (let i = 0; i < 3; i++) line(i ? '' : '  idle in', (c) => (c.groups[g].modes[i] ? `${c.groups[g].modes[i][0]} ${pct(c.groups[g].modes[i][1])}` : ''));
    }
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const result = rows(store, o.runs, o);
    if (!result.games.length) throw new Error(`no games for ${o.runs.join(', ')}`);
    if (o.rows) console.log(result.rows.map((r) => JSON.stringify(r)).join('\n'));
    else {
        const nul = o.null.length ? rows(store, o.null, o) : undefined;
        if (nul && !nul.games.length) throw new Error(`--null: no games for ${o.null.join(', ')}`);
        const cols = summary(result, nul);
        if (o.json) console.log(JSON.stringify(cols));
        else print(cols, result.games.length, nul && nul.games.length);
    }
}

module.exports = { rows, tally, summary };
