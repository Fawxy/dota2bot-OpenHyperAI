// Query layer over the test logs (store.js). Every command first brings the store up to date with the default log
// directory (cheap when nothing changed: size and mtime per file) unless --no-ingest is given.
// Usage:
//   node hlog.js ingest [log | dir | manifest ...]      ingest (default ~/.dotactl/logs and remote/jobs) and prune gone logs
//   node hlog.js q "<sql>" | @<name> [--p k=v ...]       run SQL, or queries/<name>.sql with named params (:k)
//   node hlog.js digest <log> [--game N]                 one game in a few lines: run facts, event counts, errors, marks
//   node hlog.js events <log> --pid N|--hero h [--from t --to t --ev a,b --all --game N]  one hero's events in a window, oldest first
//   node hlog.js list [word]                             named queries and views: params and first sentence (word filters)
//   node hlog.js schema [ev]                             tables, rows and columns (kind, non-null count, an example)
//   node hlog.js prune                                   drop logs whose file is gone
// Options: --db <file> (default ~/.dotactl/hlog-<store version>.sqlite), --logs <dir>, --json, --wide (no cell truncation), --no-ingest.
'use strict';

const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS, q } = require('./store');

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

/**
 * Every named query (`@name`, run with `q @name`) and view (a table name for `q "<sql>"`): its header's first sentence and the
 * params its SQL reads (`:k`, set with `--p k=v`). With a word, only those whose name or first sentence holds it.
 */
function list(word) {
    const rows = [];
    for (const [dir, kind] of [[QUERIES, 'query'], [path.join(__dirname, 'views'), 'view']]) {
        for (const f of fs.readdirSync(dir).filter(n => n.endsWith('.sql')).sort()) {
            const text = fs.readFileSync(path.join(dir, f), 'utf8');
            const header = text.split(/\r?\n/).filter(l => l.startsWith('--')).map(l => l.replace(/^--\s?/, ''));
            const parts = [text, ...[...text.matchAll(/^-- include: (\w+)/gm)]
                .map(m => path.join(QUERIES, 'fragments', `${m[1]}.sql`)).filter(fs.existsSync).map(p => fs.readFileSync(p, 'utf8'))];
            const body = parts.join('\n').split(/\r?\n/).filter(l => !l.trim().startsWith('--')).join('\n');
            const name = (kind === 'query' ? '@' : '') + f.replace(/\.sql$/, '');
            const prose = header.filter(l => !/^(ensure|needs|include):/.test(l)).join(' ');
            const about = (prose.match(/^.*?[.;](\s|$)/) || [prose])[0].trim();
            if (word && !`${name} ${about}`.toLowerCase().includes(word.toLowerCase())) continue;
            const params = kind === 'view' ? '' : [...new Set([...body.matchAll(/(?<![:\w]):([a-z_]\w*)/gi)].map(m => m[1]))].join(' ');
            rows.push({ name, kind, params, about: about.length > 110 ? `${about.slice(0, 109)}…` : about });
        }
    }
    return rows;
}

function sqlOf(arg) {
    if (!arg.startsWith('@')) return arg;
    const file = path.join(QUERIES, `${arg.slice(1)}.sql`);
    if (!fs.existsSync(file)) throw new Error(`no query ${arg}; have: ${fs.readdirSync(QUERIES).filter(f => f.endsWith('.sql')).map(f => '@' + f.replace(/\.sql$/, '')).join(' ')}`);
    return fs.readFileSync(file, 'utf8');
}

function digest(store, file, gameNo) {
    store.ingest(file);
    const games = store.query('SELECT * FROM games WHERE file = ? ORDER BY game', path.resolve(file));
    const out = [];
    for (const g of games.filter(g => gameNo === undefined || g.game === gameNo)) {
        out.push(`${path.basename(g.file)} game ${g.game}: build=${g.build ?? '?'} mode=${g.mode ?? '?'} seed=${g.seed ?? '?'} ` +
            `set=${g.set || '-'} scenario=${g.scenario || '-'} t=${fmt(g.min_t)}..${fmt(g.max_t)} stop=${fmt(g.stop_t) || '-'} game_end=${g.ended ? 'yes' : 'no'}`);
        out.push(`  lineup: ${g.lineup || '?'} human=${g.human ?? '?'} pos=${g.human_pos ?? '-'} bots=${g.bots}`);
        if (g.label) out.push(`  label: ${g.label}`);
        // The lineup is not in pid order and queries take a pid, so each pid's hero (its last ev=bot line).
        if (store.tables().includes('ev_bot')) {
            const team = n => (n === 2 ? 'rad' : n === 3 ? 'dire' : '?');
            const heroes = store.query(`SELECT pid, hero, team, pos FROM (SELECT pid, hero, team, pos,
                row_number() OVER (PARTITION BY pid ORDER BY seq DESC) AS rn FROM ev_bot WHERE game_id = ? AND pid IS NOT NULL)
                WHERE rn = 1 ORDER BY pid`, g.game_id);
            if (heroes.length) out.push(`  pids: ${heroes.map(b => `${b.pid}=${b.hero}(${team(b.team)}${b.pos ? ` pos${b.pos}` : ''})`).join(' ')}`);
        }
        const counts = store.tables().filter(t => t.startsWith('ev_'))
            .map(t => [t.slice(3), store.query(`SELECT count(*) AS n FROM ${q(t)} WHERE game_id = ?`, g.game_id)[0].n])
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
        const n = store.query(`SELECT count(*) AS n FROM ${q(t)}`)[0].n;
        if (ev === undefined) {
            rows.push({ table: t, rows: n, columns: store.colsOf(t).size });
            continue;
        }
        for (const [col, kind] of store.colsOf(t)) {
            const r = store.query(`SELECT count(${q(col)}) AS n, (SELECT ${q(col)} FROM ${q(t)} WHERE ${q(col)} IS NOT NULL LIMIT 1) AS ex FROM ${q(t)}`)[0];
            rows.push({ table: t, column: col, kind, non_null: r.n, of: n, example: r.ex });
        }
    }
    return rows;
}

// Per-frame or per-second lines that drown a window; `events --all` keeps them, `--ev` names any of them back in.
const NOISY = ['lane_pos', 'lane_read', 'notice', 'inv', 'lanefight_mem', 'lanefight_watch', 'intent_cadence'];
// A snapshot in `events` prints these fields only (`@hero_at` gives the whole one).
const SNAP_SHORT = ['hp', 'mp', 'x', 'y', 'mode', 'by', 'act', 'tid', 'lh', 'deaths'];

/**
 * One hero's story in a window: every logged event with its pid, oldest first, as `t ev k=v ...`, from the store.
 * o: game (default the log's last game, the bots game of a remote job), pid or hero, from and to (s or m:ss), ev (names, comma
 * separated: only those, and an event with no pid column is then included for every pid), all (keep the noisy events).
 */
function events(store, file, o) {
    const secs = v => (v === undefined ? undefined : /:/.test(v) ? Math.sign(parseFloat(v) || 1) * (Math.abs(parseInt(v, 10)) * 60 + parseFloat(v.split(':')[1])) : Number(v));
    const games = store.query('SELECT game_id, game FROM games WHERE file = ? ORDER BY game', path.resolve(file));
    const g = o.game === undefined ? games[games.length - 1] : games.find(r => r.game === Number(o.game));
    if (!g) throw new Error(`no game ${o.game ?? ''} in ${file}`);
    let pid = o.pid === undefined ? undefined : Number(o.pid);
    if (pid === undefined && o.hero !== undefined && store.tables().includes('ev_bot')) {
        pid = (store.query('SELECT pid FROM ev_bot WHERE game_id = ? AND hero = ? LIMIT 1', g.game_id, o.hero)[0] || {}).pid;
    }
    if (pid === undefined) throw new Error('events needs --pid or --hero (a name as in the digest pids line)');
    const from = secs(o.from) ?? -Infinity;
    const to = secs(o.to) ?? Infinity;
    const only = o.ev ? o.ev.split(',') : undefined;
    const out = [];
    for (const t of store.tables().filter(n => n.startsWith('ev_'))) {
        const ev = t.slice(3);
        if (only ? !only.includes(ev) : !o.all && NOISY.includes(ev)) continue;
        const cols = store.query(`PRAGMA table_info(${q(t)})`).map(c => c.name);
        if (!cols.includes('pid') && !only) continue;
        const where = cols.includes('pid') ? ' AND pid = ?' : '';
        const rows = store.query(`SELECT * FROM ${q(t)} WHERE game_id = ? AND t >= ? AND t <= ?${where}`,
            g.game_id, from === -Infinity ? -1e9 : from, to === Infinity ? 1e9 : to, ...(where ? [pid] : []));
        for (const r of rows) {
            const keys = Object.keys(r).filter(k => !['game_id', 'seq', 't', 'pid'].includes(k) && r[k] !== null)
                .filter(k => ev !== 'snap' || o.all || SNAP_SHORT.includes(k));
            out.push({ t: r.t, seq: r.seq, line: `t=${fmt(r.t, true)} ${ev} ${keys.map(k => `${k}=${/\s/.test(String(r[k])) ? JSON.stringify(String(r[k])) : r[k]}`).join(' ')}` });
        }
    }
    return out.sort((a, b) => a.t - b.t || a.seq - b.seq).map(r => r.line).join('\n') || '(no events)';
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const valued = new Set(['--db', '--logs', '--p', '--game', '--pid', '--hero', '--from', '--to', '--ev']);
    const pos = argv.filter((a, i) => !a.startsWith('--') && !valued.has(argv[i - 1]));
    const [cmd, ...rest] = pos;
    let store;
    const logs = opt('logs') || LOGS;
    const say = (rows, text) => console.log(argv.includes('--json') ? JSON.stringify(rows, null, 1) : text || table(rows, argv.includes('--wide')));
    // A carriage-return progress line is noise in a captured log, so it prints on a terminal only.
    const progress = process.stderr.isTTY ? (f, n) => process.stderr.write(`\ringested ${n}: ${path.basename(f)}   `) : undefined;
    const sync = () => {
        if (argv.includes('--no-ingest')) return;
        const dirs = [logs, ...(opt('logs') ? [] : [JOBS])].filter(d => fs.existsSync(d));
        if (dirs.length) report(store.ingestAll(dirs, progress));
    };
    const report = r => {
        if (r.wrote && process.stderr.isTTY) process.stderr.write('\n');
        for (const f of r.failed) console.error(`skipped ${f.file}: ${f.error}`);
        return r;
    };
    try {
        store = new Store(opt('db') || DB);
        if (cmd === 'ingest') {
            const r = report(store.ingestAll(rest.length ? rest : [logs, ...(opt('logs') ? [] : [JOBS])].filter(d => fs.existsSync(d)), progress));
            console.error(`ingested ${r.wrote}, pruned ${r.pruned.length}, failed ${r.failed.length}`);
        } else if (cmd === 'list') {
            say(list(rest[0]), argv.includes('--json') ? undefined : table(list(rest[0]), true));
        } else if (cmd === 'q' && rest[0]) {
            sync();
            const logsIn = store.query('SELECT count(*) AS n FROM logs')[0].n;
            if (!logsIn) console.error(`the store ${path.basename(opt("db") || DB)} has no logs (a new store version starts empty): run without --no-ingest, or hlog.js ingest <log>`);
            say(store.query(sqlOf(rest[0]), params(argv)));
        } else if (cmd === 'events' && rest[0]) {
            store.ingest(rest[0]);
            console.log(events(store, rest[0], { game: opt('game'), pid: opt('pid'), hero: opt('hero'), from: opt('from'), to: opt('to'), ev: opt('ev'), all: argv.includes('--all') }));
        } else if (cmd === 'digest' && rest[0]) {
            console.log(digest(store, rest[0], opt('game') === undefined ? undefined : Number(opt('game'))));
        } else if (cmd === 'schema') {
            sync();
            say(schema(store, rest[0]));
        } else if (cmd === 'prune') {
            const gone = store.prune();
            console.error(`pruned ${gone.length}`);
        } else {
            console.error(fs.readFileSync(__filename, 'utf8').split('\n').filter(l => l.startsWith('//')).slice(2, 12).map(l => l.slice(3)).join('\n'));
            process.exitCode = 2;
        }
    } catch (e) {
        const unknown = (e.message.match(/Unknown named parameter '(\w+)'/) || [])[1];
        const named = unknown && cmd === 'q' && rest[0].startsWith('@') && list().find(r => r.name === rest[0]);
        if (named) e.message = `${rest[0]} has no param ${unknown}; it takes: ${named.params || 'none'}`;
        const view = (e.message.match(/no such table: (\w+)/) || [])[1];
        const file = view && path.join(__dirname, 'views', `${view}.sql`);
        if (file && fs.existsSync(file)) {
            const needs = [...fs.readFileSync(file, 'utf8').matchAll(/^-- needs: (\w+)/gm)].map(m => m[1]);
            console.error(`view ${view} is not open: no ingested log has ${needs.join(', ')}`);
        } else console.error(e.message);
        process.exitCode = 1;
    } finally {
        if (store) store.close();
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { table, digest, schema, list, events };
