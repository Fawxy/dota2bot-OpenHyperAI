// Log store: test logs ingested once into SQLite so a question about a game, or many, is one SQL query
// (docs/proposals/2026-10-30-log-query-layer.md). Derived and disposable: the .log stays the evidence; delete the file to
// rebuild. Tables:
//   logs        one row per ingested file (size, mtime, sha1, ingest version: the cache key)
//   games       one row per game parse.js splits a log into, with the run's dotactl facts copied in (seed, set, lineup, ...)
//   ev_<name>   one per [HEV] ev= kind: game_id, seq (line order), t, then one column per field seen
//   dx_<name>   one per [DOTACTL] ev= kind: log_id, seq, t, fields
//   errors      game_id, t, text (Lua errors as parse.js counts them)
//   columns     each column's kind (num | text); a column is num only while every value seen parses as a number
// Views in views/*.sql hold derived logic once (an analyser's rules) and are re-created on every open.
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog, parseFields } = require('./parse');

// node:sqlite is still flagged experimental on Node 22-24; its one-time warning is noise in every CLI call.
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => (/SQLite/.test(typeof w === 'string' ? w : w && w.message) ? undefined : emitWarning.call(process, w, ...rest));
const { DatabaseSync } = require('node:sqlite');

const DB = path.join(os.homedir(), '.dotactl', 'hlog.sqlite');
const LOGS = path.join(os.homedir(), '.dotactl', 'logs');
const VIEWS = path.join(__dirname, 'views');
// Bump when ingest changes what it writes: every log is re-ingested on its next use.
const INGEST_VERSION = 1;
const KEEP_TEXT = new Set(['build', 'text', 'msg']); // parse.js STRING_KEYS: never read true/false as 1/0 there
const RESERVED = new Set(['game_id', 'log_id', 'seq', 't']);

const q = name => `"${name.replace(/"/g, '""')}"`;
const tableName = (prefix, ev) => `${prefix}_${String(ev).replace(/\W/g, '_')}`;
const colName = k => (RESERVED.has(k) ? `f_${k}` : k);

/** One field value as stored: '?' and absent are NULL, true/false are 1/0, numbers stay numbers. */
function cell(k, v) {
    if (v === undefined || v === null || v === '?') return null;
    if (!KEEP_TEXT.has(k) && (v === 'true' || v === 'false')) return v === 'true' ? 1 : 0;
    return v;
}

class Store {
    /** `kinds` ({table: {col: 'num' | 'text'}}) overrides inference; typed event declarations will feed it. */
    constructor(file = DB, { kinds = {}, views = VIEWS } = {}) {
        if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
        this.db = new DatabaseSync(file);
        this.declared = kinds;
        this.viewsDir = views;
        this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;
            CREATE TABLE IF NOT EXISTS logs (log_id INTEGER PRIMARY KEY, file TEXT UNIQUE, size INTEGER, mtime REAL, hash TEXT, version INTEGER);
            CREATE TABLE IF NOT EXISTS games (game_id INTEGER PRIMARY KEY, log_id INTEGER, file TEXT, game INTEGER, build TEXT,
                mode TEXT, seed INTEGER, "set" TEXT, scenario TEXT, worktree TEXT, timescale REAL, lineup TEXT, human TEXT,
                human_pos INTEGER, stop_t REAL, min_t REAL, max_t REAL, ended INTEGER, bots INTEGER, events INTEGER,
                errors INTEGER, squelches INTEGER);
            CREATE TABLE IF NOT EXISTS errors (game_id INTEGER, t REAL, text TEXT);
            CREATE TABLE IF NOT EXISTS columns (tbl TEXT, col TEXT, kind TEXT, PRIMARY KEY (tbl, col));
            CREATE INDEX IF NOT EXISTS games_log ON games (log_id);`);
        this.kinds = new Map();
        for (const r of this.db.prepare('SELECT tbl, col, kind FROM columns').all()) this.colsOf(r.tbl).set(r.col, r.kind);
        this.refreshViews();
    }

    colsOf(tbl) {
        if (!this.kinds.has(tbl)) this.kinds.set(tbl, new Map());
        return this.kinds.get(tbl);
    }

    /** Creates the table or adds columns, settles each column's kind, then inserts all rows in one prepared statement. */
    write(tbl, keys, rows) {
        if (!rows.length) return;
        const known = this.kinds.has(tbl);
        const cols = this.colsOf(tbl);
        if (!known) this.db.exec(`CREATE TABLE IF NOT EXISTS ${q(tbl)} (${keys.map(q).join(', ')})`);
        const seen = new Map();
        for (const r of rows) for (const [k, v] of Object.entries(r)) {
            if (keys.includes(k)) continue;
            if (!seen.has(k)) seen.set(k, undefined);
            if (v !== null && seen.get(k) !== 'text') seen.set(k, typeof v === 'number' ? 'num' : 'text');
        }
        for (const [k, kind0] of seen) {
            const decl = (this.declared[tbl] || {})[k];
            const old = cols.get(k);
            if (old === undefined) {
                this.addColumn(tbl, k, decl || kind0 || 'num');
                continue;
            }
            const kind = decl || (kind0 === 'text' ? 'text' : old);
            if (kind === old) continue;
            // Numbers are stored as REAL, and CAST(1.0 AS TEXT) is '1.0'; match String(v) as new rows get it.
            const c = q(k);
            if (kind === 'text') this.db.exec(`UPDATE ${q(tbl)} SET ${c} = CASE WHEN typeof(${c}) = 'real' AND ${c} = CAST(${c} AS INTEGER)
                THEN CAST(CAST(${c} AS INTEGER) AS TEXT) ELSE CAST(${c} AS TEXT) END WHERE ${c} IS NOT NULL`);
            cols.set(k, kind);
            this.db.prepare('INSERT OR REPLACE INTO columns VALUES (?, ?, ?)').run(tbl, k, kind);
        }
        const names = [...keys, ...[...seen.keys()]];
        const stmt = this.db.prepare(`INSERT INTO ${q(tbl)} (${names.map(q).join(', ')}) VALUES (${names.map(() => '?').join(', ')})`);
        for (const r of rows) stmt.run(...names.map(k => {
            const v = r[k] === undefined ? null : r[k];
            return v !== null && cols.get(k) === 'text' && typeof v === 'number' ? String(v) : v;
        }));
        if (!known) {
            const idx = seen.has('pid') ? [keys[0], 'pid', 't'] : [keys[0], 't'];
            this.db.exec(`CREATE INDEX IF NOT EXISTS ${q(`${tbl}_idx`)} ON ${q(tbl)} (${idx.map(q).join(', ')})`);
        }
    }

    tables() {
        return this.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND (name LIKE 'ev\\_%' ESCAPE '\\' OR name LIKE 'dx\\_%' ESCAPE '\\')").all().map(r => r.name);
    }

    drop(logId) {
        const games = `SELECT game_id FROM games WHERE log_id = ${Number(logId)}`;
        for (const t of [...this.tables(), 'errors']) {
            this.db.exec(t.startsWith('dx_') ? `DELETE FROM ${q(t)} WHERE log_id = ${Number(logId)}` : `DELETE FROM ${q(t)} WHERE game_id IN (${games})`);
        }
        this.db.exec(`DELETE FROM games WHERE log_id = ${Number(logId)}; DELETE FROM logs WHERE log_id = ${Number(logId)}`);
    }

    /** Ingests one log unless the cache says it is current. Returns true when it (re)wrote the log. */
    ingest(file) {
        file = path.resolve(file);
        const st = fs.statSync(file);
        const row = this.db.prepare('SELECT * FROM logs WHERE file = ?').get(file);
        if (row && row.version === INGEST_VERSION && row.size === st.size && row.mtime === st.mtimeMs) return false;
        const text = fs.readFileSync(file, 'utf8');
        const hash = crypto.createHash('sha1').update(text).digest('hex');
        if (row && row.version === INGEST_VERSION && row.hash === hash) {
            this.db.prepare('UPDATE logs SET size = ?, mtime = ? WHERE log_id = ?').run(st.size, st.mtimeMs, row.log_id);
            return false;
        }
        this.db.exec('BEGIN');
        try {
            if (row) this.drop(row.log_id);
            const logId = Number(this.db.prepare('INSERT INTO logs (file, size, mtime, hash, version) VALUES (?, ?, ?, ?, ?)')
                .run(file, st.size, st.mtimeMs, hash, INGEST_VERSION).lastInsertRowid);
            const facts = this.writeFacts(logId, text);
            for (const g of parseLog(text)) this.writeGame(logId, file, g, facts);
            this.db.exec('COMMIT');
        } catch (e) {
            this.db.exec('ROLLBACK');
            throw e;
        }
        return true;
    }

    /** [DOTACTL] lines into dx_<ev>; returns the run facts copied into games. */
    writeFacts(logId, text) {
        const byEv = new Map();
        let seq = 0;
        for (const line of text.split(/\r?\n/)) {
            const i = line.indexOf('[DOTACTL] ');
            if (i < 0) continue;
            const f = parseFields(line.slice(i + 10));
            if (typeof f.ev !== 'string') continue;
            const r = { log_id: logId, seq: seq++, t: typeof f.t === 'number' ? f.t : null };
            for (const [k, v] of Object.entries(f)) if (k !== 'ev' && k !== 't') r[colName(k)] = cell(k, v);
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
        const gameId = Number(this.db.prepare(`INSERT INTO games (log_id, file, game, build, mode, seed, "set", scenario, worktree,
            timescale, lineup, human, human_pos, stop_t, min_t, max_t, ended, bots, events, errors, squelches)
            VALUES (${Array(21).fill('?').join(', ')})`).run(logId, file, g.index, bot ? String(bot.build) : null,
            ...['mode', 'seed', 'set', 'scenario', 'worktree', 'timescale', 'lineup', 'human', 'human_pos', 'stop_t'].map(k => facts[k] ?? null),
            Number.isFinite(g.minT) ? g.minT : null, Number.isFinite(g.maxT) ? g.maxT : null, g.ended ? 1 : 0,
            Object.values(g.bots).filter(b => !b.human).length, g.events.length, g.errors.length, g.squelches).lastInsertRowid);
        const byEv = new Map();
        g.events.forEach((e, seq) => {
            const r = { game_id: gameId, seq, t: e.t };
            for (const [k, v] of Object.entries(e)) if (k !== 'ev' && k !== 't') r[colName(k)] = cell(k, v);
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
        for (const r of gone) this.drop(r.log_id);
        return gone.map(r => r.file);
    }

    /** Ingests files, directories (their *.log) and manifests (their status=ok logs); prunes first. */
    ingestAll(args, onLog = () => {}) {
        const pruned = this.prune();
        let wrote = 0;
        for (const f of expand(args)) if (this.ingest(f)) onLog(f, ++wrote);
        if (wrote || pruned.length) this.refreshViews();
        return { wrote, pruned };
    }

    /**
     * Re-creates each view in views/*.sql. A view's `-- needs: ev_x(a, b)` lines add those columns (NULL) first, so a view
     * still opens on logs from builds that never wrote a field; a view whose tables do not exist yet is skipped.
     */
    refreshViews() {
        if (!this.viewsDir || !fs.existsSync(this.viewsDir)) return;
        for (const f of fs.readdirSync(this.viewsDir).filter(f => f.endsWith('.sql')).sort()) {
            const sql = fs.readFileSync(path.join(this.viewsDir, f), 'utf8');
            const name = path.basename(f, '.sql');
            this.db.exec(`DROP VIEW IF EXISTS ${q(name)}`);
            const needs = [...sql.matchAll(/^-- needs: (\w+)\(([^)]*)\)/gm)];
            if (needs.some(([, tbl]) => !this.kinds.has(tbl))) continue;
            for (const [, tbl, list] of needs) for (const c of list.split(',').map(s => s.trim()).filter(Boolean)) this.addColumn(tbl, c);
            this.db.exec(`CREATE VIEW ${q(name)} AS ${sql.replace(/;\s*$/, '')}`);
        }
    }

    addColumn(tbl, col, kind = (this.declared[tbl] || {})[col] || 'num') {
        if (this.colsOf(tbl).has(col)) return;
        this.db.exec(`ALTER TABLE ${q(tbl)} ADD COLUMN ${q(col)}`);
        this.colsOf(tbl).set(col, kind);
        this.db.prepare('INSERT OR REPLACE INTO columns VALUES (?, ?, ?)').run(tbl, col, kind);
    }

    query(sql, ...args) {
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
        else if (/\.manifest$/.test(a)) out.push(...fs.readFileSync(a, 'utf8').split('\n').filter(l => /status=ok/.test(l)).map(l => l.match(/log="([^"]+)"/)[1]));
        else out.push(a);
    }
    return out;
}

module.exports = { Store, DB, LOGS, INGEST_VERSION };
