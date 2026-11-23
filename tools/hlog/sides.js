// A ledger read by side: per-game totals of a ledger's lines for ours and OHA, and the tables gold.js and xp.js print from them.
// A ledger gives its `shape` and its game analysis; the runs, labels, arms, mirror columns and the sum check are the same for both.
//   shape = { lines: [names, summed], change: the totals field the lines sum to, changeRow: its row name,
//             memo: [names of rows printed after the sum, each the total of its parts, never summed] }
//   analyse(store, game, at) -> { heroes: [{ hero: { pid, team, pos }, rec: { [change], lines, parts } }], ... } or { skip }
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS, labelOf } = require('./store');
const { parseLabel } = require('./label');

const ARMS = ['off', 'J', 'T', 'B', 'BF', 'noT', 'noF', 'noA', 'noC', 'noJ', 'all'];

function args(argv) {
    const o = { runs: [], null: [], at: 600, json: false };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--null') into = o.null;
        else if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--arm') o.arm = argv[++i];
        else if (a === '--by') o.by = argv[++i];
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

/** Ingests only the logs of these runs (the store caches an unchanged log), local and remote-job layouts. */
function ingestRuns(store, runs) {
    const wanted = (label) => label && runs.some((r) => label.startsWith(`${r}_`));
    const files = [];
    for (const f of fs.existsSync(LOGS) ? fs.readdirSync(LOGS) : []) if (f.endsWith('.log') && wanted(labelOf(path.join(LOGS, f)))) files.push(path.join(LOGS, f));
    for (const d of fs.existsSync(JOBS) ? fs.readdirSync(JOBS) : []) {
        const f = path.join(JOBS, d, 'game.log');
        if (fs.existsSync(f) && wanted(labelOf(f))) files.push(f);
    }
    for (const f of files) store.ingest(f);
}

/** Each log's last game for the runs, with parsed label; a game with no readable seat is returned in `skipped`. */
function games(store, runs, { arm } = {}) {
    const out = [];
    const skipped = [];
    for (const run of runs) {
        const rows = store.query(`SELECT g.game_id, g.file, g.label FROM games g
            WHERE g.label LIKE :p ESCAPE '\\' AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file) ORDER BY g.label`,
        { p: `${run.replace(/_/g, '\\_')}\\_%` });
        for (const r of rows) {
            const p = parseLabel(r.label);
            if (!p) { skipped.push({ label: r.label, why: 'no <lineup>_<arm>[seat]_<n> in the label' }); continue; }
            if (arm !== undefined && p.arm !== arm) continue;
            out.push({ ...r, ...p });
        }
    }
    return { games: out, skipped };
}

const totals = (shape) => ({ [shape.change]: 0, lines: Object.fromEntries(shape.lines.map((l) => [l, 0])), parts: {}, unmatchedLh: 0 });
function fold(t, rec, shape) {
    t[shape.change] += rec[shape.change];
    t.unmatchedLh += rec.unmatchedLh || 0;
    for (const l of shape.lines) t.lines[l] += rec.lines[l];
    for (const [k, v] of Object.entries(rec.parts)) t.parts[k] = (t.parts[k] || 0) + v;
}

/** One game as { ours: team totals, oha: team totals } plus per-position hero rows. */
function gameResult(store, g, at, shape, analyse) {
    const a = analyse(store, g, at);
    if (a.skip) return { skip: a.skip };
    const side = (team) => (team === g.seat ? 'ours' : 'oha');
    const res = { label: g.label, arm: g.arm, mirror: g.mirror, ours: totals(shape), oha: totals(shape), pos: {}, est: a.est };
    for (const { hero, rec } of a.heroes) {
        fold(res[side(hero.team)], rec, shape);
        const key = `${side(hero.team)}:${hero.pos}`;
        res.pos[key] = res.pos[key] || totals(shape);
        fold(res.pos[key], rec, shape);
    }
    return res;
}

function run(store, runs, o, shape, analyse) {
    const { games: gs, skipped } = games(store, runs, o);
    const results = [];
    for (const g of gs) {
        const r = gameResult(store, g, o.at, shape, analyse);
        if (r.skip) skipped.push({ label: g.label, why: r.skip });
        else results.push(r);
    }
    return { games: results, skipped };
}

const avg = (a) => a.reduce((x, y) => x + y, 0) / (a.length || 1);

/** Rows: the change, each line with its parts, the sum of the lines, then the memo rows, as per-game means of `pick(game)` totals. */
function rows(shape, result, nul, pickOurs = (g) => g.ours, pickOha = (g) => g.oha, wider = []) {
    const keys = new Set();
    const all = [...result.games, ...(nul ? nul.games : [])];
    for (const g of all) for (const t of [g.ours, g.oha]) for (const k of Object.keys(t.parts)) keys.add(k);
    for (const t of wider) for (const k of Object.keys(t.parts)) keys.add(k);
    const partsOf = (l) => [...keys].filter((k) => k.startsWith(`${l}:`)).sort();
    const partRows = (l) => partsOf(l).map((k) => ({ row: `  ${k.slice(l.length + 1)}`, get: (t) => t.parts[k] || 0, part: true }));
    const spec = [{ row: shape.changeRow, get: (t) => t[shape.change] }];
    for (const l of shape.lines) spec.push({ row: l, get: (t) => t.lines[l] }, ...partRows(l));
    spec.push({ row: 'sum_of_lines', get: (t) => shape.lines.reduce((a, l) => a + t.lines[l], 0) });
    for (const m of shape.memo || []) spec.push({ row: m, get: (t) => partsOf(m).reduce((a, k) => a + (t.parts[k] || 0), 0), part: true }, ...partRows(m));
    return spec.map(({ row, get, part }) => {
        const ours = avg(result.games.map((g) => get(pickOurs(g))));
        const oha = avg(result.games.map((g) => get(pickOha(g))));
        const r = { row, ours, oha, gap: ours - oha, part: !!part };
        if (nul) {
            r.mirror = avg(nul.games.flatMap((g) => [get(g.ours), get(g.oha)]));
            r.we = ours - r.mirror;
            r.they = r.mirror - oha;
        }
        return r;
    });
}

const f1 = (v) => (Math.round(v * 10) / 10).toFixed(1);
function printRows(shape, rs, head) {
    const cols = Object.keys(rs[0]).filter((k) => k !== 'row' && k !== 'part');
    console.log(head);
    console.log(`${'line'.padEnd(26)} ${cols.map((c) => c.padStart(8)).join(' ')}`);
    for (const r of rs) console.log(`${r.row.padEnd(26)} ${cols.map((c) => f1(r[c]).padStart(8)).join(' ')}`);
    const chg = rs.find((r) => r.row === shape.changeRow);
    const sum = rs.find((r) => r.row === 'sum_of_lines');
    console.log(`check: sum_of_lines - ${shape.changeRow} = ${cols.map((c) => `${c} ${(sum[c] - chg[c]).toFixed(6)}`).join(', ')}`);
}

function armTable(shape, result) {
    const by = new Map();
    for (const g of result.games) (by.get(g.arm) || by.set(g.arm, []).get(g.arm)).push(g);
    const arms = [...by.keys()].sort((a, b) => (ARMS.indexOf(a) + 1 || 99) - (ARMS.indexOf(b) + 1 || 99));
    const keys = result.games.flatMap((g) => [g.ours, g.oha]);
    const per = arms.map((a) => rows(shape, { games: by.get(a) }, undefined, undefined, undefined, keys));
    // By place, not by name: two lines may each have a part of one name, and every arm's rows share one order (`keys`).
    const table = per[0].map((r, i) => ({ row: r.row, ...Object.fromEntries(arms.map((a, j) => [a, per[j][i].gap])) }));
    table.push({ row: `ours_${shape.changeRow}`, ...Object.fromEntries(arms.map((a, j) => [a, per[j].find((r) => r.row === shape.changeRow).ours])) });
    table.push({ row: 'check_sum_minus_change', ...Object.fromEntries(arms.map((a, j) => [a, per[j].find((r) => r.row === 'sum_of_lines').gap - per[j].find((r) => r.row === shape.changeRow).gap])) });
    table.push({ row: 'games', ...Object.fromEntries(arms.map((a) => [a, by.get(a).length])) });
    return { arms, table };
}

/** The command line both ledgers share. `file` is the ledger's own source (its header comment is the help); `tail(result)` an optional last line. */
function main(argv, { file, shape, analyse, tail }) {
    const o = args(argv);
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(file, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) ingestRuns(store, [...o.runs, ...o.null]);
    const result = run(store, o.runs, o, shape, analyse);
    const nul = o.null.length ? run(store, o.null, { ...o, arm: undefined }, shape, analyse) : undefined;
    for (const s of [...result.skipped, ...(nul ? nul.skipped : [])]) console.error(`skipped ${s.label}: ${s.why}`);
    if (!result.games.length) throw new Error('no games');
    const head = `${result.games.length} games${nul ? `, mirror ${nul.games.length} games` : ''}; per game, ours / OHA, gap = ours - OHA; first snapshot to ${o.at} s`
        + (nul ? '; mirror = OHA against OHA, both seats; we = ours - mirror, they = mirror - OHA' : '')
        + (result.games.some((g) => g.mirror) ? `; ${result.games.filter((g) => g.mirror).length} mirror games (no seat in the label): ours = Radiant, OHA = Dire` : '');
    if (o.by === 'arm') {
        const { arms, table } = armTable(shape, result);
        if (o.json) console.log(JSON.stringify({ arms, table }));
        else {
            console.log(`${result.games.length} games; gap = ours - OHA per game, first snapshot to ${o.at} s`);
            console.log(`${'line'.padEnd(26)} ${arms.map((a) => a.padStart(7)).join(' ')}`);
            for (const r of table) console.log(`${r.row.padEnd(26)} ${arms.map((a) => f1(r[a]).padStart(7)).join(' ')}`);
        }
    } else if (o.by === 'pos') {
        const out = {};
        for (const pos of [1, 2, 3, 4, 5]) {
            const sel = (side) => (g) => g.pos[`${side}:${pos}`] || totals(shape);
            const m = nul ? { games: nul.games.map((g) => ({ ours: sel('ours')(g), oha: sel('oha')(g) })) } : undefined;
            const withParts = { games: result.games.map((g) => ({ ours: sel('ours')(g), oha: sel('oha')(g) })) };
            out[pos] = rows(shape, withParts, m);
            if (!o.json) printRows(shape, out[pos], `== pos ${pos}: one hero a side; ${head}`);
        }
        if (o.json) console.log(JSON.stringify(out));
    } else {
        const rs = rows(shape, result, nul);
        if (o.json) console.log(JSON.stringify({ games: result.games.length, skipped: result.skipped, rows: rs, unmatchedLh: avg(result.games.map((g) => g.ours.unmatchedLh + g.oha.unmatchedLh)) }));
        else {
            printRows(shape, rs, head);
            if (tail) console.log(tail(result));
        }
    }
}

module.exports = { parseLabel, args, ingestRuns, games, totals, fold, gameResult, run, rows, printRows, armTable, main, avg, f1 };
