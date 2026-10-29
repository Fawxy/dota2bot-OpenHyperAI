// Query layer over the test logs (store.js). Every command first brings the store up to date with the default log
// directory (cheap when nothing changed: size and mtime per file) unless --no-ingest is given.
// Usage:
//   node hlog.js ingest [log | dir | manifest ...]      ingest (default ~/.dotactl/logs) and prune logs that are gone
//   node hlog.js q "<sql>" | @<name> [--p k=v ...]       run SQL, or queries/<name>.sql with named params (:k)
//   node hlog.js digest <log> [--game N]                 one game in a few lines: run facts, event counts, errors, marks
//   node hlog.js schema [ev]                             tables, rows and columns (kind, non-null count, an example)
//   node hlog.js prune                                   drop logs whose file is gone
// Options: --db <file> (default ~/.dotactl/hlog.sqlite), --logs <dir>, --json, --wide (no cell truncation), --no-ingest.
'use strict';

const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS } = require('./store');

const QUERIES = path.join(__dirname, 'queries');
const CELL = 48;

function fmt(v, wide) {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'number' && !Number.isInteger(v) ? String(Math.round(v * 1000) / 1000) : String(v);
    return wide || s.length <= CELL ? s : `${s.slice(0, CELL - 1)}…`;
}

/** Rows as an aligned text table; numbers right-aligned. */
function table(rows, wide) {
    if (!rows.length) return '(0 rows)';
    const cols = Object.keys(rows[0]);
    const cells = rows.map(r => cols.map(c => fmt(r[c], wide)));
    const w = cols.map((c, i) => Math.max(c.length, ...cells.map(r => r[i].length)));
    const num = cols.map(c => rows.every(r => r[c] === null || typeof r[c] === 'number'));
    const line = r => r.map((s, i) => (num[i] ? s.padStart(w[i]) : s.padEnd(w[i]))).join('  ').trimEnd();
    return [line(cols), ...cells.map(line), `(${rows.length} rows)`].join('\n');
}

function params(argv) {
    const out = {};
    argv.forEach((a, i) => {
        if (a !== '--p') return;
        const [k, ...v] = argv[i + 1].split('=');
        const s = v.join('=');
        out[k] = /^-?\d+(\.\d+)?$/.test(s) ? Number(s) : s;
    });
    return out;
}

function sqlOf(arg) {
    if (!arg.startsWith('@')) return arg;
    const file = path.join(QUERIES, `${arg.slice(1)}.sql`);
    if (!fs.existsSync(file)) throw new Error(`no query ${arg}; have: ${fs.readdirSync(QUERIES).map(f => '@' + f.replace(/\.sql$/, '')).join(' ')}`);
    return fs.readFileSync(file, 'utf8');
}

function digest(store, file, gameNo) {
    store.ingest(file);
    const games = store.query('SELECT * FROM games WHERE file = ? ORDER BY game', path.resolve(file));
    const out = [];
    for (const g of games.filter(g => gameNo === undefined || g.game === gameNo)) {
        out.push(`${path.basename(g.file)} game ${g.game}: build=${g.build ?? '?'} mode=${g.mode ?? '?'} seed=${g.seed ?? '?'} ` +
            `set=${g.set || '-'} scenario=${g.scenario || '-'} t=${fmt(g.min_t)}..${fmt(g.max_t)} stop=${fmt(g.stop_t) || '-'} ended=${g.ended}`);
        out.push(`  lineup: ${g.lineup || '?'} human=${g.human ?? '?'} pos=${g.human_pos ?? '-'} bots=${g.bots}`);
        const counts = store.tables().filter(t => t.startsWith('ev_'))
            .map(t => [t.slice(3), store.query(`SELECT count(*) AS n FROM "${t}" WHERE game_id = ?`, g.game_id)[0].n])
            .filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
        out.push(`  events ${g.events}: ${counts.map(([e, n]) => `${e}=${n}`).join(' ')}`);
        out.push(`  errors ${g.errors}, squelches ${g.squelches}`);
        for (const e of store.query('SELECT t, text FROM errors WHERE game_id = ? LIMIT 5', g.game_id)) out.push(`    t=${fmt(e.t)} ${fmt(e.text)}`);
        if (counts.some(([e]) => e === 'mark')) {
            for (const m of store.query('SELECT * FROM ev_mark WHERE game_id = ? ORDER BY seq', g.game_id)) out.push(`  mark t=${fmt(m.t)} ${m.by ?? ''}: ${m.text ?? ''}`);
        }
    }
    return out.join('\n') || `no game in ${file}`;
}

function schema(store, ev) {
    const rows = [];
    for (const t of store.tables().filter(t => ev === undefined || t === `ev_${ev}` || t === `dx_${ev}` || t === ev)) {
        const n = store.query(`SELECT count(*) AS n FROM "${t}"`)[0].n;
        if (ev === undefined) {
            rows.push({ table: t, rows: n, columns: store.colsOf(t).size });
            continue;
        }
        for (const [col, kind] of store.colsOf(t)) {
            const r = store.query(`SELECT count("${col}") AS n, (SELECT "${col}" FROM "${t}" WHERE "${col}" IS NOT NULL LIMIT 1) AS ex FROM "${t}"`)[0];
            rows.push({ table: t, column: col, kind, non_null: r.n, of: n, example: r.ex });
        }
    }
    return rows;
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const valued = new Set(['--db', '--logs', '--p', '--game']);
    const pos = argv.filter((a, i) => !a.startsWith('--') && !valued.has(argv[i - 1]));
    const [cmd, ...rest] = pos;
    const store = new Store(opt('db') || DB);
    const logs = opt('logs') || LOGS;
    const say = (rows, text) => console.log(argv.includes('--json') ? JSON.stringify(rows, null, 1) : text || table(rows, argv.includes('--wide')));
    const progress = (f, n) => process.stderr.write(`\ringested ${n}: ${path.basename(f)}   `);
    const sync = () => {
        if (argv.includes('--no-ingest') || !fs.existsSync(logs)) return;
        const r = store.ingestAll([logs], progress);
        if (r.wrote) process.stderr.write('\n');
    };
    try {
        if (cmd === 'ingest') {
            const r = store.ingestAll(rest.length ? rest : [logs], progress);
            console.error(`${r.wrote ? '\n' : ''}ingested ${r.wrote}, pruned ${r.pruned.length}`);
        } else if (cmd === 'q' && rest[0]) {
            sync();
            say(store.query(sqlOf(rest[0]), params(argv)));
        } else if (cmd === 'digest' && rest[0]) {
            console.log(digest(store, rest[0], opt('game') === undefined ? undefined : Number(opt('game'))));
        } else if (cmd === 'schema') {
            sync();
            say(schema(store, rest[0]));
        } else if (cmd === 'prune') {
            const gone = store.prune();
            console.error(`pruned ${gone.length}`);
        } else {
            console.error(fs.readFileSync(__filename, 'utf8').split('\n').filter(l => l.startsWith('//')).slice(2, 10).map(l => l.slice(3)).join('\n'));
            process.exitCode = 2;
        }
    } catch (e) {
        const view = (e.message.match(/no such table: (\w+)/) || [])[1];
        const file = view && path.join(__dirname, 'views', `${view}.sql`);
        if (file && fs.existsSync(file)) {
            const needs = [...fs.readFileSync(file, 'utf8').matchAll(/^-- needs: (\w+)/gm)].map(m => m[1]);
            console.error(`view ${view} is not open: no ingested log has ${needs.join(', ')}`);
        } else console.error(e.message);
        process.exitCode = 1;
    } finally {
        store.close();
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { table, digest, schema };
