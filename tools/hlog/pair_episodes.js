// Pair episodes per side (the `fighting-together` proposal (master tag `pre-process-v5`) "Tools"; D10, D19): queries/pair_episodes.sql for the
// games of one or more runs, read per game for each hitting side: `ours` our pairs on an OHA hero, `oha` OHA's on ours. Ours is
// the seat in the label, as ledger.js.
// Usage: node pair_episodes.js <run> [<run> ...] [--null <run> ...] [--until 720] [--rows] [--json] [--no-ingest]
//   --null <runs>  OHA against OHA runs: a `mirror` column, both seats' mean per game
//   --rows         the pair rows as JSON lines (label, side added), not the table
// Lines (the query's header has the definitions):
//   pair fights      a hit on an enemy hero with a second of the side within 1,200 of it, per game
//   partner hit      the share where the partner hit the target too ("both" below); `gap` its median seconds after the first
//   one target       of both, the share where neither hit another enemy hero during the fight
//   both: killed     of both, the target died within 12 s of the end; `low` the same for fights whose target fell to 40% or less
//   one: killed      the same where the partner never hit
//   stop gap         of both where the target lived, the median seconds between the two members' last hits
//   left together    of fights where a member retreated, the share where the other retreated within 3 s of it
//   member died      a member died within 12 s of the end, of both and of one; `even` of both with as many of theirs as ours
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { games } = require('./ledger');

const SQL = fs.readFileSync(path.join(__dirname, 'queries', 'pair_episodes.sql'), 'utf8');

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

/** The pair rows of the runs' games, each with label and side (the hitting team's: ours when it is the label's seat). */
function rows(store, runs, { until = 720 } = {}) {
    const gs = games(store, runs);
    const out = [];
    for (const g of gs) {
        for (const r of store.query(SQL, { like: g.file, until, pos_lo: 1, pos_hi: 5 })) {
            out.push({ label: g.label, side: r.team === g.seat ? 'ours' : 'oha', ...r });
        }
    }
    return { games: gs, rows: out };
}

const share = (a, b) => (b ? a / b : NaN);
const frac = (rs, f) => ({ v: share(rs.filter(f).length, rs.length), n: rs.length });
function median(xs) {
    if (!xs.length) return NaN;
    const s = [...xs].sort((a, b) => a - b);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** Per-game lines for one side's rows over n games. */
function tally(rs, n) {
    const both = rs.filter((r) => r.gap2 !== null && r.gap2 !== undefined);
    const one = rs.filter((r) => r.gap2 === null || r.gap2 === undefined);
    const died = (r) => r.d1 || r.d2;
    const ret = rs.filter((r) => r.ret1 != null || r.ret2 != null);
    return {
        fights: rs.length / n,
        partner: frac(rs, (r) => both.includes(r)),
        gap: median(both.map((r) => r.gap2)),
        oneTarget: frac(both, (r) => !r.split),
        bothKilled: frac(both, (r) => r.tdied),
        lowKilled: frac(both.filter((r) => r.minhp <= 40), (r) => r.tdied),
        oneKilled: frac(one, (r) => r.tdied),
        stopGap: median(both.filter((r) => !r.tdied).map((r) => Math.abs(r.last1 - r.last2))),
        together: frac(ret, (r) => r.ret1 != null && r.ret2 != null && Math.abs(r.ret1 - r.ret2) <= 3),
        diedBoth: frac(both, died),
        diedEven: frac(both.filter((r) => r.en === r.al), died),
        diedOne: frac(one, died),
    };
}

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
    const pct = (f) => (Number.isNaN(f.v) ? '-' : `${Math.round(100 * f.v)}% of ${f.n}`);
    const sec = (v) => (Number.isNaN(v) ? '-' : `${v} s`);
    const line = (label, f) => console.log(`${label.padEnd(18)} ${names.map((c) => f(cols[c]).padStart(18)).join('')}`);
    console.log(`ours (our pairs) / oha (OHA's on us)${nm ? ` / mirror (${nm} games, per seat)` : ''}; ${n} games; shares of all games' fights`);
    line('', (c) => names.find((k) => cols[k] === c));
    line('pair fights/game', (c) => c.fights.toFixed(1));
    line('partner hit', (c) => pct(c.partner));
    line('  gap (median)', (c) => sec(c.gap));
    line('one target', (c) => pct(c.oneTarget));
    line('both: killed', (c) => pct(c.bothKilled));
    line('  low: killed', (c) => pct(c.lowKilled));
    line('one: killed', (c) => pct(c.oneKilled));
    line('stop gap (median)', (c) => sec(c.stopGap));
    line('left together', (c) => pct(c.together));
    line('member died: both', (c) => pct(c.diedBoth));
    line('  even numbers', (c) => pct(c.diedEven));
    line('member died: one', (c) => pct(c.diedOne));
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
