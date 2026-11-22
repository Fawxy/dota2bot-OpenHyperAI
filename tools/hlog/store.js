// Log store: test logs ingested once into SQLite so a question about a game, or many, is one SQL query
// (the `log-query-layer` proposal (master tag `pre-process-v5`)). Derived and disposable: the .log stays the evidence; delete the file to
// rebuild. Tables:
//   logs        one row per ingested file (size, mtime, sha1: the cache key)
//   games       one row per game parse.js splits a log into, with the run's dotactl facts copied in (seed, set, lineup, ...)
//   ev_<name>   one per [HEV] ev= kind: game_id, seq (line order), t, then one column per field seen
//   dx_<name>   one per [DOTACTL] ev= kind: log_id, seq, t, fields
//   errors      game_id, t, text (Lua errors as parse.js counts them)
//   columns     each column's kind: num while every value seen is a number, else text. Metadata only: each value keeps its
//               own type (integers INTEGER, other numbers REAL, the rest TEXT), so a view's `x > 0` means what it says on
//               every row; a declared text column (declared = 1) is the exception and stores numbers as String(v)
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

const HOME = path.join(os.homedir(), '.dotactl');
const LOGS = path.join(HOME, 'logs');
// Remote-batch games: one folder per job, `<id>/game.log` beside the `job.json` that names its label.
const JOBS = path.join(HOME, 'remote', 'jobs');
const VIEWS = path.join(__dirname, 'views');
const FRAGMENTS = path.join(__dirname, 'queries', 'fragments');

/** Expands `-- include: <name>` lines with queries/fragments/<name>.sql (CTEs several queries share; fragments may include
 *  others), so a rule a view cannot hold (one that needs the query's parameters) still has one copy. A fragment lands once
 *  in a query, at its first include: each names what it needs, and two may need the same one. */
function include(sql, seen = [], done = new Set()) {
    return sql.replace(/^-- include: (\w+)[^\S\n]*$/gm, (_, name) => {
        if (seen.includes(name)) throw new Error(`fragment ${name} includes itself (${[...seen, name].join(' > ')})`);
        if (done.has(name)) return '';
        const file = path.join(FRAGMENTS, `${name}.sql`);
        if (!fs.existsSync(file)) throw new Error(`no fragment ${name} (queries/fragments/${name}.sql)`);
        done.add(name);
        return include(fs.readFileSync(file, 'utf8'), [...seen, name], done);
    });
}
// Bump when ingest changes what it writes or the tables' shape (or a declared text column must become a number again):
// the next open starts a new, empty store file.
const INGEST_VERSION = 7;

// Declared column kinds from the typed event declaration (gen_events.js writes events.json); absent file means inference only.
const DECLARED = (() => {
    let text;
    try { text = fs.readFileSync(path.join(__dirname, 'events.json'), 'utf8'); } catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
    return JSON.parse(text).kinds || {};
})();

// One store per ingest version, shared by every worktree: a declaration change (most events.json edits) is applied in place
// by `applyDeclared`, and a declared text column stays text, so the store holds the union of the worktrees' declarations
// whatever order they open it in. Keying the file on the declaration instead rebuilt the whole log bank (~12 min on 11 GB)
// about a dozen times a day.
const STORE_RE = /^hlog-(\d+)\.sqlite$/;
const storeFile = (version = INGEST_VERSION, dir = HOME) => path.join(dir, `hlog-${version}.sqlite`);
const DB = storeFile();
const STALE_MS = 7 * 24 * 3600 * 1000;

/** Deletes the other version stores beside `file` that no Store has opened for STALE_MS (each open touches its file). */
function sweep(file, now = Date.now()) {
    const dir = path.dirname(file);
    for (const f of fs.readdirSync(dir).filter(f => STORE_RE.test(f) && f !== path.basename(file))) {
        const p = path.join(dir, f);
        let st;
        try { st = fs.statSync(p); } catch (e) { if (e.code === 'ENOENT') continue; throw e; }
        if (now - st.mtimeMs < STALE_MS) continue;
        for (const x of ['', '-wal', '-shm']) fs.rmSync(p + x, { force: true });
    }
}
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
        const named = file !== ':memory:' && path.basename(file).match(STORE_RE);
        // Opening another version's store would empty it: an old store is read with sqlite3, never rebuilt by mistake.
        if (named && Number(named[1]) !== INGEST_VERSION) {
            throw new Error(`${path.basename(file)} is the store of another ingest version (this hlog writes ${path.basename(storeFile())}); read it with sqlite3`);
        }
        if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
        this.db = new DatabaseSync(file, { timeout: BUSY_MS });
        this.declared = kinds;
        this.viewsDir = views;
        this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL');
        const version = this.db.prepare('PRAGMA user_version').get().user_version;
        if (version !== INGEST_VERSION) this.rebuild();
        this.loadKinds();
        this.applyDeclared();
        this.refreshViews();
        if (file !== ':memory:' && STORE_RE.test(path.basename(file))) {
            // Housekeeping only: a store that cannot be touched or swept (a race with another sweep, a locked file) still opens.
            try {
                const now = new Date();
                fs.utimesSync(file, now, now);
                sweep(file, now.getTime());
            } catch (e) { /* best effort */ }
        }
    }

    rebuild() {
        this.db.exec('BEGIN IMMEDIATE');
        // Two processes can open a new store file at once: the second must not empty what the first has built since.
        if (this.db.prepare('PRAGMA user_version').get().user_version === INGEST_VERSION) {
            this.db.exec('COMMIT');
            return;
        }
        for (const { name } of this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").all()) {
            this.db.exec(`DROP TABLE ${q(name)}`);
        }
        this.db.exec(`CREATE TABLE logs (log_id INTEGER PRIMARY KEY, file TEXT UNIQUE, size INTEGER, mtime REAL, hash TEXT);
            CREATE TABLE games (game_id INTEGER PRIMARY KEY, log_id INTEGER, file TEXT, game INTEGER, build TEXT,
                mode TEXT, seed INTEGER, "set" TEXT, scenario TEXT, worktree TEXT, timescale REAL, lineup TEXT, human TEXT,
                human_pos INTEGER, stop_t REAL, min_t REAL, max_t REAL, ended INTEGER, bots INTEGER, events INTEGER,
                errors INTEGER, squelches INTEGER, error_squelches INTEGER, label TEXT);
            CREATE TABLE errors (game_id INTEGER, t REAL, text TEXT);
            CREATE TABLE columns (tbl TEXT, col TEXT, kind TEXT, declared INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (tbl, col));
            CREATE INDEX games_log ON games (log_id);
            CREATE INDEX errors_game ON errors (game_id);
            PRAGMA user_version = ${INGEST_VERSION};
            COMMIT`);
    }

    loadKinds() {
        this.kinds = new Map();
        this.texts = new Set(); // `${tbl}.${col}` of declared text columns
        for (const r of this.db.prepare('SELECT tbl, col, kind, declared FROM columns').all()) {
            this.colsOf(r.tbl).set(r.col, r.kind);
            if (r.declared) this.texts.add(`${r.tbl}.${r.col}`.toLowerCase());
        }
    }

    /** Declared columns of the tables already stored that this store does not hold as declared yet. */
    undeclared() {
        const out = [];
        for (const [tbl, cols] of Object.entries(this.declared)) {
            if (!this.kinds.has(tbl)) continue; // created with its declared columns on its first write
            for (const [col, kind] of Object.entries(cols)) {
                if (kind === 'text' ? !this.isText(tbl, col) : this.storedAs(tbl, col) === undefined) out.push([tbl, col, kind]);
            }
        }
        return out;
    }

    /** Brings the stored tables up to this declaration in place; takes the write lock only when something is missing. */
    applyDeclared() {
        if (!this.undeclared().length) return;
        this.db.exec('BEGIN IMMEDIATE');
        try {
            this.loadKinds(); // another process may have applied it while this one waited
            for (const [tbl, col, kind] of this.undeclared()) this.declare(tbl, col, kind);
            this.db.exec('COMMIT');
        } catch (e) {
            this.db.exec('ROLLBACK');
            this.loadKinds();
            throw e;
        }
    }

    /**
     * Adds a declared column, or turns a stored one into a declared text column: the numbers already in it become
     * String(v), exactly what ingest writes into a declared text column. Runs inside the caller's write transaction.
     */
    declare(tbl, col, kind) {
        if (kind !== 'text') return this.addColumn(tbl, col, kind);
        if (this.isText(tbl, col)) return;
        const stored = this.storedAs(tbl, col);
        if (stored === undefined) this.addColumn(tbl, col, kind);
        else {
            const set = this.db.prepare(`UPDATE ${q(tbl)} SET ${q(stored)} = ? WHERE rowid = ?`);
            for (const r of this.db.prepare(`SELECT rowid AS id, ${q(stored)} AS v FROM ${q(tbl)} WHERE typeof(${q(stored)}) IN ('integer', 'real')`).all()) {
                set.run(String(r.v), r.id);
            }
        }
        this.setKind(tbl, stored ?? col, 'text', true);
    }

    /** The stored column `col` names: SQLite column names ignore case, so one that differs only in case is the same column. */
    storedAs(tbl, col) {
        return [...this.colsOf(tbl).keys()].find(c => c.toLowerCase() === col.toLowerCase());
    }

    isText(tbl, col) {
        return this.texts.has(`${tbl}.${col}`.toLowerCase());
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
        // Declared columns exist from the first write, so a view over a field no line has carried yet reads NULL, not an error.
        for (const [c, kind] of Object.entries(this.declared[tbl] || {})) if (!keys.includes(c)) this.declare(tbl, c, kind);
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
        // Declared text by any worktree's declaration, not only this one's: a column stays text once declared.
        const asText = new Set(all.filter(c => this.isText(tbl, c)));
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
        try {
            this.db.exec(`ALTER TABLE ${q(tbl)} ADD COLUMN ${q(col)}`);
        } catch (e) {
            if (!/duplicate column name/.test(e.message)) throw e;
            this.loadKinds(); // another process added it first
            return;
        }
        this.setKind(tbl, col, kind);
    }

    setKind(tbl, col, kind, declared = this.isText(tbl, col)) {
        this.colsOf(tbl).set(col, kind);
        if (declared) this.texts.add(`${tbl}.${col}`.toLowerCase());
        this.db.prepare('INSERT OR REPLACE INTO columns VALUES (?, ?, ?, ?)').run(tbl, col, kind, declared ? 1 : 0);
    }

    tables() {
        return this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'ev\\_%' ESCAPE '\\' OR name LIKE 'dx\\_%' ESCAPE '\\')").all().map(r => r.name);
    }

    drop(logId) {
        const id = Number(logId);
        const games = `SELECT game_id FROM games WHERE log_id = ${id}`;
        // Game ids are rowids and can be reused, so rows left behind would read as another game's.
        for (const t of ['hero_sec', 'hero_sec_games']) {
            if (this.hasTable(t)) this.db.exec(`DELETE FROM ${t} WHERE game_id IN (${games})`);
        }
        for (const t of [...this.tables(), 'errors']) {
            this.db.exec(t.startsWith('dx_') ? `DELETE FROM ${q(t)} WHERE log_id = ${id}` : `DELETE FROM ${q(t)} WHERE game_id IN (${games})`);
        }
        this.db.exec(`DELETE FROM games WHERE log_id = ${id}; DELETE FROM logs WHERE log_id = ${id}`);
    }

    /** Ingests one log unless the cache says it is current. Returns true when it (re)wrote the log. */
    ingest(file) {
        file = path.resolve(file);
        const st = fs.statSync(file);
        const rowOf = () => this.db.prepare('SELECT * FROM logs WHERE file = ?').get(file);
        const current = row => row && row.size === st.size && row.mtime === st.mtimeMs;
        if (current(rowOf())) return false;
        this.db.exec('BEGIN IMMEDIATE');
        try {
            // Read again under the write lock: another hlog process may have ingested this log, or added tables and
            // columns, since this one looked.
            const row = rowOf();
            this.loadKinds();
            let same = current(row);
            const text = same ? '' : fs.readFileSync(file, 'utf8');
            const hash = same ? '' : crypto.createHash('sha1').update(text).digest('hex');
            if (!same && row && row.hash === hash) {
                this.db.prepare('UPDATE logs SET size = ?, mtime = ? WHERE log_id = ?').run(st.size, st.mtimeMs, row.log_id);
                same = true;
            }
            if (same) {
                this.db.exec('COMMIT');
                return false;
            }
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
            min_t, max_t, ended, bots, events, errors, squelches, error_squelches, label) VALUES (${Array(23).fill('?').join(', ')})`).run(logId, file, g.index,
            bot ? String(bot.build) : null, ...factKeys.map(k => bind(facts[k] ?? null)),
            Number.isFinite(g.minT) ? g.minT : null, Number.isFinite(g.maxT) ? g.maxT : null, g.ended ? 1 : 0,
            Object.values(g.bots).filter(b => !b.human).length, g.events.length, g.errors.length, g.squelches, g.errorSquelches, labelOf(file)).lastInsertRowid);
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
        const tablesBefore = this.kinds.size;
        let wrote = 0;
        const failed = [];
        for (const f of expand(args)) {
            try {
                if (this.ingest(f)) onLog(f, ++wrote);
            } catch (e) {
                failed.push({ file: f, error: e.message });
            }
        }
        // Another process may have written the tables a view needs while this one ingested nothing.
        this.loadKinds();
        if (wrote || pruned.length || this.kinds.size !== tablesBefore) this.refreshViews();
        return { wrote, pruned, failed };
    }

    /**
     * (Re-)creates each view in views/*.sql as a TEMP view on this connection (`-- include:` fragments expanded, as in
     * `query`), so opening the store takes no write lock
     * (except a `-- ensure:` header that finds its table or column missing, which writes once).
     * A view's `-- needs: ev_x(a, b)` lines add those columns (NULL) first, so it still opens on logs from builds that
     * never wrote a field; a view whose tables no log has is skipped.
     */
    refreshViews() {
        if (!this.viewsDir || !fs.existsSync(this.viewsDir)) return;
        for (const f of fs.readdirSync(this.viewsDir).filter(f => f.endsWith('.sql')).sort()) {
            const sql = include(fs.readFileSync(path.join(this.viewsDir, f), 'utf8'));
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

    hasTable(name) {
        return this.db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?").get(name) !== undefined;
    }

    heroSecTables() {
        this.db.exec(`CREATE TABLE IF NOT EXISTS hero_sec (game_id, pid, team, pos, hero, sec, x, y, hp, mode, live, life, lane, hits, near, en900, al900);
            CREATE TABLE IF NOT EXISTS hero_sec_games (game_id INTEGER PRIMARY KEY, version TEXT);
            CREATE INDEX IF NOT EXISTS hero_sec_pid ON hero_sec (game_id, pid, sec);
            CREATE INDEX IF NOT EXISTS hero_sec_sec ON hero_sec (game_id, sec)`);
    }

    /** The stamp of the fill rules: any change to the fill SQL, a fragment it includes or the lane polylines changes it. */
    heroSecVersion() {
        const text = include(fs.readFileSync(path.join(FRAGMENTS, 'hero_sec_fill.sql'), 'utf8'))
            + fs.readFileSync(path.join(VIEWS, 'lane_segments.sql'), 'utf8');
        return crypto.createHash('sha1').update(text).digest('hex').slice(0, 12);
    }

    /**
     * Brings `hero_sec` (one row per game, hero and whole second; see fragments/hero_sec_fill.sql) up to date for the games
     * whose file matches `like` (default all) and, when given, whose game number is `game`: a game with no rows stamped by the
     * current rules is (re)filled, the others are skipped. Created on first use, so an existing store needs no re-ingest.
     * Columns carry no type, as in the ev_ tables: an INTEGER-typed game_id would stop a join to ev_snap from using its index.
     * Returns the number of games filled.
     */
    fillHeroSec({ like = '%', game = null } = {}, onGame = () => {}) {
        const version = this.heroSecVersion();
        this.heroSecTables();
        const sql = include(fs.readFileSync(path.join(FRAGMENTS, 'hero_sec_fill.sql'), 'utf8'));
        this.ensure(sql);
        const pending = () => this.db.prepare(`SELECT g.game_id FROM games g LEFT JOIN hero_sec_games h ON h.game_id = g.game_id
            WHERE g.file LIKE :like AND (:game IS NULL OR g.game = :game) AND h.version IS NOT :version ORDER BY g.game_id`)
            .all({ like, game, version }).map(r => Number(r.game_id));
        const BATCH = 10;
        let filled = 0;
        const total = pending().length;
        if (total > BATCH) console.error(`hero_sec: filling ${total} games (about 0.3 s each)`);
        while (pending().length) {
            this.db.exec('BEGIN IMMEDIATE');
            try {
                // Another process may have filled these while this one waited for the lock.
                const todo = pending().slice(0, BATCH);
                this.db.exec('CREATE TEMP TABLE IF NOT EXISTS hs_todo (game_id INTEGER PRIMARY KEY); DELETE FROM hs_todo');
                const ins = this.db.prepare('INSERT INTO hs_todo VALUES (?)');
                for (const id of todo) ins.run(id);
                this.db.exec(`DELETE FROM hero_sec WHERE game_id IN (SELECT game_id FROM hs_todo);
                    DELETE FROM hero_sec_games WHERE game_id IN (SELECT game_id FROM hs_todo)`);
                this.db.exec(sql);
                const stamp = this.db.prepare('INSERT INTO hero_sec_games VALUES (?, ?)');
                for (const id of todo) stamp.run(id, version);
                this.db.exec('COMMIT');
                filled += todo.length;
                onGame(filled);
            } catch (e) {
                this.db.exec('ROLLBACK');
                throw e;
            }
        }
        return filled;
    }

    query(sql, ...args) {
        sql = include(sql);
        if (/\bhero_sec\b/.test(sql)) {
            // Only the games a `like` or `file` param names are filled: filling a whole store takes minutes and locks it, so SQL
            // with neither reads what is there and is told on stderr when that is not everything.
            const p = args[0] && typeof args[0] === 'object' ? args[0] : {};
            const like = typeof p.like === 'string' ? p.like : typeof p.file === 'string' ? p.file : null;
            if (like !== null) {
                this.fillHeroSec({ like, game: p.game ?? null });
                // `like` and `game` may be there only to say which games to fill; SQLite refuses a param the SQL does not name.
                const used = Object.fromEntries(Object.entries(p).filter(([k]) => !['like', 'file', 'game'].includes(k) || new RegExp(`:${k}\\b`).test(sql)));
                args = [used, ...args.slice(1)].filter((a, i) => i > 0 || Object.keys(a).length > 0);
            } else {
                this.heroSecTables();
                const r = this.db.prepare(`SELECT count(*) AS n, sum(h.version IS :v) AS ok FROM games g LEFT JOIN hero_sec_games h ON h.game_id = g.game_id`)
                    .get({ v: this.heroSecVersion() });
                if (r.n > (r.ok || 0)) console.error(`hero_sec holds ${r.ok || 0} of ${r.n} games; pass --p like=<run or path fragment> (use it in the SQL or not) to fill the games you read`);
            }
        }
        if (sql.includes('-- ensure:')) this.ensure(sql);
        return this.db.prepare(sql).all(...args);
    }

    close() {
        this.db.close();
    }
}

/**
 * A game's run label: a remote job's `job.json` `label`, else the log's file name less dotactl's timestamp prefix
 * (`2026-11-07T08-18-43-h2hlane1_A_on_1.log` is `h2hlane1_A_on_1`).
 */
function labelOf(file) {
    const job = path.join(path.dirname(file), 'job.json');
    if (path.basename(file) === 'game.log' && fs.existsSync(job)) {
        try {
            return JSON.parse(fs.readFileSync(job, 'utf8')).label ?? null;
        } catch {
            return null;
        }
    }
    return path.basename(file).replace(/\.log$/, '').replace(/^\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-/, '');
}

/** Files, a directory's *.log and its job folders' game.log (the remote jobs layout), and a manifest's ok logs. */
function expand(args) {
    const out = [];
    for (const a of args) {
        if (fs.statSync(a).isDirectory()) {
            out.push(...fs.readdirSync(a).filter(f => f.endsWith('.log')).sort().map(f => path.join(a, f)));
            out.push(...fs.readdirSync(a).sort().map(f => path.join(a, f, 'game.log')).filter(f => fs.existsSync(f)));
        }
        else if (/\.manifest$/.test(a)) out.push(...readManifest(a).map(g => g.log));
        else out.push(a);
    }
    return out;
}

module.exports = { Store, DB, LOGS, JOBS, INGEST_VERSION, labelOf, DECLARED, storeFile, STALE_MS, q };
