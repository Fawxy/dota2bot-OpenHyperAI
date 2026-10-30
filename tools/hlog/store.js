// Log store: test logs ingested once into SQLite so a question about a game, or many, is one SQL query
// (docs/proposals/2026-10-30-log-query-layer.md). Derived and disposable: the .log stays the evidence; delete the file to
// rebuild. Tables:
//   logs        one row per ingested file (size, mtime, sha1: the cache key)
//   games       one row per game parse.js splits a log into, with the run's dotactl facts copied in (seed, set, lineup, ...)
//   ev_<name>   one per [HEV] ev= kind: game_id, seq (line order), t, then one column per field seen
//   dx_<name>   one per [DOTACTL] ev= kind: log_id, seq, t, fields
//   errors      game_id, t, text (Lua errors as parse.js counts them)
//   columns     each column's kind: num while every value seen is a number, else text. Metadata only: each value keeps its
//               own type (integers INTEGER, other numbers REAL, the rest TEXT), so a view's `x > 0` means what it says on
//               every row; a declared text kind is the exception and stores numbers as String(v)
// Views in views/*.sql hold derived logic once (an analyser's rules); they are TEMP views, made per connection.
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog, parseFields } = require('./parse');
const { readManifest } = require('./manifest');

// node:sqlite is still flagged experimental on Node 22-24; its one-time warning is noise in every CLI call.
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => (/SQLite/.test(typeof w === 'string' ? w : w && w.message) ? undefined : emitWarning.call(process, w, ...rest));
const { DatabaseSync } = require('node:sqlite');

const DB = path.join(os.homedir(), '.dotactl', 'hlog.sqlite');
const LOGS = path.join(os.homedir(), '.dotactl', 'logs');
const VIEWS = path.join(__dirname, 'views');
const FRAGMENTS = path.join(__dirname, 'queries', 'fragments');

/** Expands `-- include: <name>` lines with queries/fragments/<name>.sql (CTEs several queries share; fragments may include
 *  others), so a rule a view cannot hold (one that needs the query's parameters) still has one copy. */
function include(sql, seen = []) {
    return sql.replace(/^-- include: (\w+)[^\S\n]*$/gm, (_, name) => {
        if (seen.includes(name)) throw new Error(`fragment ${name} includes itself (${[...seen, name].join(' > ')})`);
        const file = path.join(FRAGMENTS, `${name}.sql`);
        if (!fs.existsSync(file)) throw new Error(`no fragment ${name} (queries/fragments/${name}.sql)`);
        return include(fs.readFileSync(file, 'utf8'), [...seen, name]);
    });
}
// Bump when ingest changes what it writes or the tables' shape: the store is emptied and rebuilt on its next open.
const INGEST_VERSION = 4;

// Declared column kinds from the typed event declaration (gen_events.js writes events.json); absent file means inference only.
const DECLARED = (() => {
    let text;
    try { text = fs.readFileSync(path.join(__dirname, 'events.json'), 'utf8'); } catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
    return JSON.parse(text).kinds || {};
})();

// The store's version is INGEST_VERSION plus a hash of the declared kinds, so a changed declaration rebuilds the store.
const kindsHash = kinds => {
    let h = 0;
    for (const ch of JSON.stringify(kinds)) h = (h * 31 + ch.charCodeAt(0)) % 99991;
    return h;
};
const versionOf = kinds => INGEST_VERSION * 100000 + kindsHash(kinds);
const KEEP_TEXT = new Set(['build', 'text', 'msg']); // parse.js STRING_KEYS: never read true/false as 1/0 there
const RESERVED = new Set(['game_id', 'log_id', 'seq', 't']);
const BUSY_MS = 30000;

const q = name => `"${String(name).replace(/"/g, '""')}"`;
const tableName = (prefix, ev) => `${prefix}_${String(ev).replace(/\W/g, '_')}`;

/** One field value as stored: '?' and absent are NULL, true/false are 1/0, integers bind as INTEGER. */
function cell(k, v) {
    if (v === undefined || v === null || v === '?') return null;
    if (!KEEP_TEXT.has(k) && (v === 'true' || v === 'false')) return v === 'true' ? 1 : 0;
    return v;
}

/** A field named like a row key (any case) would overwrite it in the row object: it becomes f_<name>. */
const fieldKey = k => (RESERVED.has(k.toLowerCase()) ? `f_${k}` : k);

const bind = v => (typeof v === 'number' && Number.isSafeInteger(v) ? BigInt(v) : v);

class Store {
    /** `kinds` ({table: {col: 'num' | 'text'}}) overrides inference; the default is the typed event declaration (events.json). */
    constructor(file = DB, { kinds = DECLARED, views = VIEWS } = {}) {
        if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
        this.db = new DatabaseSync(file, { timeout: BUSY_MS });
        this.declared = kinds;
        this.viewsDir = views;
        this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL');
        const version = this.db.prepare('PRAGMA user_version').get().user_version;
        if (version !== versionOf(kinds)) this.rebuild();
        this.loadKinds();
        this.refreshViews();
    }

    rebuild() {
        this.db.exec('BEGIN IMMEDIATE');
        for (const { name } of this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all()) {
            this.db.exec(`DROP TABLE ${q(name)}`);
        }
        this.db.exec(`CREATE TABLE logs (log_id INTEGER PRIMARY KEY, file TEXT UNIQUE, size INTEGER, mtime REAL, hash TEXT);
            CREATE TABLE games (game_id INTEGER PRIMARY KEY, log_id INTEGER, file TEXT, game INTEGER, build TEXT,
                mode TEXT, seed INTEGER, "set" TEXT, scenario TEXT, worktree TEXT, timescale REAL, lineup TEXT, human TEXT,
                human_pos INTEGER, stop_t REAL, min_t REAL, max_t REAL, ended INTEGER, bots INTEGER, events INTEGER,
                errors INTEGER, squelches INTEGER, error_squelches INTEGER);
            CREATE TABLE errors (game_id INTEGER, t REAL, text TEXT);
            CREATE TABLE columns (tbl TEXT, col TEXT, kind TEXT, PRIMARY KEY (tbl, col));
            CREATE INDEX games_log ON games (log_id);
            CREATE INDEX errors_game ON errors (game_id);
            PRAGMA user_version = ${versionOf(this.declared)};
            COMMIT`);
    }

    loadKinds() {
        this.kinds = new Map();
        for (const r of this.db.prepare('SELECT tbl, col, kind FROM columns').all()) this.colsOf(r.tbl).set(r.col, r.kind);
    }

    colsOf(tbl) {
        if (!this.kinds.has(tbl)) this.kinds.set(tbl, new Map());
        return this.kinds.get(tbl);
    }

    /**
     * SQLite column names are case-insensitive: a field that differs from a known column (or a key) only in case
     * becomes f_<name>, first come first served.
     */
    columnFor(tbl, keys, k, taken) {
        let name = k;
        for (;;) {
            const clash = [...keys, ...this.colsOf(tbl).keys(), ...taken.keys()].find(c => c.toLowerCase() === name.toLowerCase());
            if (clash === undefined || clash === name) return name;
            name = `f_${name}`;
        }
    }

    /** Creates the table or adds columns, settles each column's kind, then inserts all rows in one prepared statement. */
    write(tbl, keys, rows) {
        if (!rows.length) return;
        if (!this.kinds.has(tbl)) this.db.exec(`CREATE TABLE IF NOT EXISTS ${q(tbl)} (${keys.map(q).join(', ')})`);
        const cols = this.colsOf(tbl);
        const names = new Map(); // field -> column
        const seen = new Map(); // column -> kind of this log's values
        for (const r of rows) for (const [k, v] of Object.entries(r)) {
            if (keys.includes(k)) continue;
            if (!names.has(k)) names.set(k, this.columnFor(tbl, keys, k, seen));
            const c = names.get(k);
            if (!seen.has(c)) seen.set(c, undefined);
            if (v !== null && seen.get(c) !== 'text') seen.set(c, typeof v === 'number' ? 'num' : 'text');
        }
        for (const [c, kind] of seen) {
            const decl = (this.declared[tbl] || {})[c];
            if (!cols.has(c)) this.addColumn(tbl, c, decl || kind || 'num');
            else if (decl && cols.get(c) !== decl) this.setKind(tbl, c, decl);
            else if (!decl && kind === 'text' && cols.get(c) === 'num') this.setKind(tbl, c, 'text');
        }
        const all = [...keys, ...seen.keys()];
        const fieldOf = new Map([...names].map(([k, c]) => [c, k]));
        const asText = new Set(all.filter(c => (this.declared[tbl] || {})[c] === 'text'));
        const stmt = this.db.prepare(`INSERT INTO ${q(tbl)} (${all.map(q).join(', ')}) VALUES (${all.map(() => '?').join(', ')})`);
        for (const r of rows) stmt.run(...all.map(c => {
            const v = r[fieldOf.get(c) || c];
            if (v === undefined || v === null) return null;
            return asText.has(c) && typeof v === 'number' ? String(v) : bind(v);
        }));
        const idx = cols.has('pid') ? [keys[0], 'pid', 't'] : [keys[0], 't'];
        this.db.exec(`CREATE INDEX IF NOT EXISTS ${q(`${tbl}_${idx.length === 3 ? 'pid' : 't'}`)} ON ${q(tbl)} (${idx.map(q).join(', ')})`);
    }

    addColumn(tbl, col, kind = (this.declared[tbl] || {})[col] || 'num') {
        if (this.colsOf(tbl).has(col)) return;
        this.db.exec(`ALTER TABLE ${q(tbl)} ADD COLUMN ${q(col)}`);
        this.setKind(tbl, col, kind);
    }

    setKind(tbl, col, kind) {
        this.colsOf(tbl).set(col, kind);
        this.db.prepare('INSERT OR REPLACE INTO columns VALUES (?, ?, ?)').run(tbl, col, kind);
    }

    tables() {
        return this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'ev\\_%' ESCAPE '\\' OR name LIKE 'dx\\_%' ESCAPE '\\')").all().map(r => r.name);
    }

    drop(logId) {
        const id = Number(logId);
        const games = `SELECT game_id FROM games WHERE log_id = ${id}`;
        for (const t of [...this.tables(), 'errors']) {
            this.db.exec(t.startsWith('dx_') ? `DELETE FROM ${q(t)} WHERE log_id = ${id}` : `DELETE FROM ${q(t)} WHERE game_id IN (${games})`);
        }
        this.db.exec(`DELETE FROM games WHERE log_id = ${id}; DELETE FROM logs WHERE log_id = ${id}`);
    }

    /** Ingests one log unless the cache says it is current. Returns true when it (re)wrote the log. */
    ingest(file) {
        file = path.resolve(file);
        const st = fs.statSync(file);
        const row = this.db.prepare('SELECT * FROM logs WHERE file = ?').get(file);
        if (row && row.size === st.size && row.mtime === st.mtimeMs) return false;
        const text = fs.readFileSync(file, 'utf8');
        const hash = crypto.createHash('sha1').update(text).digest('hex');
        if (row && row.hash === hash) {
            this.db.prepare('UPDATE logs SET size = ?, mtime = ? WHERE log_id = ?').run(st.size, st.mtimeMs, row.log_id);
            return false;
        }
        this.db.exec('BEGIN IMMEDIATE');
        try {
            if (row) this.drop(row.log_id);
            const logId = Number(this.db.prepare('INSERT INTO logs (file, size, mtime, hash) VALUES (?, ?, ?, ?)')
                .run(file, st.size, st.mtimeMs, hash).lastInsertRowid);
            const facts = this.writeFacts(logId, text);
            for (const g of parseLog(text)) this.writeGame(logId, file, g, facts);
            this.db.exec('COMMIT');
        } catch (e) {
            this.db.exec('ROLLBACK');
            this.loadKinds(); // the rollback undid this log's CREATE/ALTER TABLE too
            throw e;
        }
        return true;
    }

    /** [DOTACTL] lines into dx_<ev>; returns the run facts, which are per log and copied into every game of it. */
    writeFacts(logId, text) {
        const byEv = new Map();
        let seq = 0;
        for (const line of text.split(/\r?\n/)) {
            const i = line.indexOf('[DOTACTL] ');
            if (i < 0) continue;
            const f = parseFields(line.slice(i + 10));
            if (typeof f.ev !== 'string') continue;
            const r = { log_id: logId, seq: seq++, t: typeof f.t === 'number' ? f.t : null };
            for (const [k, v] of Object.entries(f)) if (k !== 'ev' && k !== 't') r[fieldKey(k)] = cell(k, v);
            if (!byEv.has(f.ev)) byEv.set(f.ev, []);
            byEv.get(f.ev).push(r);
        }
        for (const [ev, rows] of byEv) this.write(tableName('dx', ev), ['log_id', 'seq', 't'], rows);
        const first = ev => (byEv.get(ev) || [])[0] || {};
        const start = first('start');
        const lineup = first('lineup');
        const stops = byEv.get('stop') || [];
        return {
            mode: start.mode, seed: start.seed, set: start.set, scenario: start.scenario, worktree: start.worktree,
            timescale: start.timescale, lineup: lineup.bots, human: lineup.human ?? start.human, human_pos: first('pos').human,
            stop_t: stops.length ? stops[stops.length - 1].t : undefined,
        };
    }

    writeGame(logId, file, g, facts) {
        const bot = g.events.find(e => e.ev === 'bot' && e.build !== undefined);
        const factKeys = ['mode', 'seed', 'set', 'scenario', 'worktree', 'timescale', 'lineup', 'human', 'human_pos', 'stop_t'];
        const gameId = Number(this.db.prepare(`INSERT INTO games (log_id, file, game, build, ${factKeys.map(q).join(', ')},
            min_t, max_t, ended, bots, events, errors, squelches, error_squelches) VALUES (${Array(22).fill('?').join(', ')})`).run(logId, file, g.index,
            bot ? String(bot.build) : null, ...factKeys.map(k => bind(facts[k] ?? null)),
            Number.isFinite(g.minT) ? g.minT : null, Number.isFinite(g.maxT) ? g.maxT : null, g.ended ? 1 : 0,
            Object.values(g.bots).filter(b => !b.human).length, g.events.length, g.errors.length, g.squelches, g.errorSquelches).lastInsertRowid);
        const byEv = new Map();
        g.events.forEach((e, seq) => {
            const r = { game_id: gameId, seq, t: e.t };
            for (const [k, v] of Object.entries(e)) if (k !== 'ev' && k !== 't') r[fieldKey(k)] = cell(k, v);
            if (!byEv.has(e.ev)) byEv.set(e.ev, []);
            byEv.get(e.ev).push(r);
        });
        for (const [ev, rows] of byEv) this.write(tableName('ev', ev), ['game_id', 'seq', 't'], rows);
        const errStmt = this.db.prepare('INSERT INTO errors VALUES (?, ?, ?)');
        for (const e of g.errors) errStmt.run(gameId, Number.isFinite(e.t) ? e.t : null, e.text);
    }

    /** Drops every log whose file is gone, so data voided under the bad-data rule cannot be queried. */
    prune() {
        const gone = this.db.prepare('SELECT log_id, file FROM logs').all().filter(r => !fs.existsSync(r.file));
        if (!gone.length) return [];
        this.db.exec('BEGIN IMMEDIATE');
        try {
            for (const r of gone) this.drop(r.log_id);
            this.db.exec('COMMIT');
        } catch (e) {
            this.db.exec('ROLLBACK');
            throw e;
        }
        return gone.map(r => r.file);
    }

    /**
     * Ingests files, directories (their *.log) and manifests (their status=ok logs); prunes first. A log that fails is
     * reported and skipped, so one bad file does not stop every query.
     */
    ingestAll(args, onLog = () => {}) {
        const pruned = this.prune();
        let wrote = 0;
        const failed = [];
        for (const f of expand(args)) {
            try {
                if (this.ingest(f)) onLog(f, ++wrote);
            } catch (e) {
                failed.push({ file: f, error: e.message });
            }
        }
        if (wrote || pruned.length) this.refreshViews();
        return { wrote, pruned, failed };
    }

    /**
     * (Re-)creates each view in views/*.sql as a TEMP view on this connection, so opening the store takes no write lock
     * (except a `-- ensure:` header that finds its table or column missing, which writes once).
     * A view's `-- needs: ev_x(a, b)` lines add those columns (NULL) first, so it still opens on logs from builds that
     * never wrote a field; a view whose tables no log has is skipped.
     */
    refreshViews() {
        if (!this.viewsDir || !fs.existsSync(this.viewsDir)) return;
        for (const f of fs.readdirSync(this.viewsDir).filter(f => f.endsWith('.sql')).sort()) {
            const sql = fs.readFileSync(path.join(this.viewsDir, f), 'utf8');
            const name = path.basename(f, '.sql');
            this.db.exec(`DROP VIEW IF EXISTS temp.${q(name)}`);
            const needs = [...sql.matchAll(/^-- needs: (\w+)\(([^)]*)\)/gm)];
            if (needs.some(([, tbl]) => !this.kinds.has(tbl))) continue;
            this.ensure(sql);
            for (const [, tbl, list] of needs) for (const c of list.split(',').map(s => s.trim()).filter(Boolean)) this.addColumn(tbl, c);
            this.db.exec(`CREATE TEMP VIEW ${q(name)} AS ${sql.replace(/;\s*$/, '')}`);
        }
    }

    /**
     * `-- ensure: ev_x(a, b)` header lines (views and queries): a table the SQL reads but a log may not have (ev_player without
     * a human, ev_front before slice 2b) is created empty with those columns, so the SQL runs and returns no rows from it.
     */
    ensure(sql) {
        for (const [, tbl, list] of sql.matchAll(/^-- ensure: (\w+)\(([^)]*)\)/gm)) {
            const cols = list.split(',').map(x => x.trim()).filter(Boolean);
            if (this.kinds.has(tbl) && cols.every(c => this.colsOf(tbl).has(c))) continue; // nothing to write: no lock taken
            try {
                if (!this.kinds.has(tbl)) this.db.exec(`CREATE TABLE IF NOT EXISTS ${q(tbl)} (game_id, seq, t)`);
                for (const c of cols) this.addColumn(tbl, c);
            } catch (e) {
                if (!/duplicate column name/.test(e.message)) throw e;
                this.loadKinds(); // another process added it first
            }
        }
    }

    query(sql, ...args) {
        sql = include(sql);
        if (sql.includes('-- ensure:')) this.ensure(sql);
        return this.db.prepare(sql).all(...args);
    }

    close() {
        this.db.close();
    }
}

function expand(args) {
    const out = [];
    for (const a of args) {
        if (fs.statSync(a).isDirectory()) out.push(...fs.readdirSync(a).filter(f => f.endsWith('.log')).sort().map(f => path.join(a, f)));
        else if (/\.manifest$/.test(a)) out.push(...readManifest(a).map(g => g.log));
        else out.push(a);
    }
    return out;
}

module.exports = { Store, DB, LOGS, INGEST_VERSION, DECLARED, versionOf, q };
