'use strict';
// `node hlog.js replay <dem | label | log>...  [--game N] [--all] [--until S]`: reads a recorded game's SourceTV replay with the master's
// `unittruth` (docs/team/research/replay-index/tools/unittruth; binary path in UNITTRUTH_EXE or the default below) and writes its rows into
// the store, for the game of the log with the same basename (the .dem dotactl --record keeps beside it): `rp_game`, `rp_unit`, `unit_pos`,
// `unit_hit` (store.js replayTables). It runs only when asked, and again after the log changes or the store is rebuilt (about 1 s a game).
// From then on `@unit_life` reads the game's units from the replay (src and by_src replay), `scene` shows its paths and hits, and
// `@unit_grade` compares the log's units with them (docs/proposals/2026-11-25-scene-and-unit-lives.md s5).
//   rp_game  game_id, dem, size, mtime, until (s), units, hits
//   rp_unit  one per unit that was live, to `until` (720 s, the log's CreepDeathUntil): uid (`<entity>.<n>`: entity indices are reused),
//            ent, kind (lane|neutral), team (2, 3; 4 a neutral), type (melee, ranged, siege, flag, or the neutral's name), name (the unit
//            name), lane (top|mid|bot|base|other: where the creep was 20 s after it spawned, or at its death if sooner; NULL a neutral),
//            wave (floor(t0 / 30); NULL a neutral), camp (the log's camp number of the nearest camp within 700 of a neutral's first spot,
//            camp_boxes.json; NULL when none), t0 x0 y0 (first live), t1 x1 y1 hp (death, set only when end = death; hp the last above 0),
//            maxhp, end (death | gone | alive), by_kind (hero | deny | tower | creep | neutral | unknown; NULL while alive), by_team, by_name,
//            by_pid (a hero or denier), by_illusion, amb (1: two like units died within 0.1 s with different killers, so the killers may be
//            swapped), kdt (s between the death and its combat log entry)
//   unit_pos game_id, uid, t (whole seconds), x, y, hp   every live unit, every second
//   unit_hit game_id, t, ak, at, ap, an, tk, tt, tp, tn, dmg, inf   a damage entry with a hero on one side (kind, team, pid, name of the
//            attacker (a) and target (t); the inflictor, empty for an attack)
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { laneLabel } = require('./dynamic');

const EXE = process.env.UNITTRUTH_EXE ||
    path.join(__dirname, '../../../../docs/team/research/replay-index/data/bin/unittruth');
const BOXES = JSON.parse(fs.readFileSync(path.join(__dirname, 'camp_boxes.json'), 'utf8'));
const CAMP_R = 700;
const LANE_AFTER = 20;

/** The NDJSON lines unittruth writes for a replay, parsed (meta, unit, pos, hit, end). */
function readReplay(dem, until) {
    if (!fs.existsSync(EXE)) throw new Error(`no unittruth at ${EXE}: build it (docs/team/research/replay-index/tools/unittruth, go build -o ../../data/bin/unittruth .) or set UNITTRUTH_EXE`);
    const p = spawnSync(EXE, [dem, ...(until === undefined ? [] : ['--until', String(until)])], { maxBuffer: 1 << 30, encoding: 'utf8' });
    if (p.status !== 0) throw new Error(`unittruth failed on ${dem}: ${p.stderr || p.error}`);
    return p.stdout.split('\n').filter(l => l.startsWith('{')).map(l => JSON.parse(l));
}

function nearestCamp(x, y) {
    let best;
    for (const [idx, b] of Object.entries(BOXES)) {
        const d = Math.hypot(b.x - x, b.y - y);
        if (d <= CAMP_R && (!best || d < best.d)) best = { idx: Number(idx), d };
    }
    return best?.idx ?? null;
}

/** Writes one game's replay rows (the parsed lines), replacing any it had. `stat`: the .dem's {size, mtimeMs}. */
function ingestReplay(store, gameId, dem, lines, stat = { size: null, mtimeMs: null }) {
    const units = lines.filter(l => l.k === 'unit');
    const end = lines.find(l => l.k === 'end');
    const until = lines.find(l => l.k === 'meta')?.until ?? null;
    const at = new Map(); // uid -> [[t, x, y]]
    for (const l of lines) if (l.k === 'pos') for (const [uid, x, y] of l.u) { if (!at.has(uid)) at.set(uid, []); at.get(uid).push([l.t, x, y]); }
    const laneOf = u => {
        if (u.kind !== 'lane') return null;
        const track = at.get(u.uid) || [];
        const tl = Math.min(u.t0 + LANE_AFTER, u.t1 ?? Infinity);
        const p = track.find(r => r[0] >= tl) || track[track.length - 1];
        return laneLabel(p ? [p[1], p[2]] : [u.x0, u.y0]);
    };
    const db = store.db;
    db.exec('BEGIN IMMEDIATE');
    try {
        for (const t of ['rp_game', 'rp_unit', 'unit_pos', 'unit_hit']) db.prepare(`DELETE FROM ${t} WHERE game_id = ?`).run(gameId);
        const bind = v => (v === undefined || v === null ? null : typeof v === 'number' && Number.isSafeInteger(v) && Number.isInteger(v) ? BigInt(v) : v);
        const ins = (sql, rows) => { const st = db.prepare(sql); for (const r of rows) st.run(...r.map(bind)); };
        ins(`INSERT INTO rp_unit VALUES (${Array(26).fill('?').join(', ')})`, units.map(u => {
            const dead = u.end === 'death';
            return [gameId, u.uid, u.ent, u.kind, u.team, u.type, u.name, laneOf(u), u.kind === 'lane' ? Math.floor(u.t0 / 30) : null,
                u.kind === 'neutral' ? nearestCamp(u.x0, u.y0) : null, u.t0, u.x0, u.y0, dead ? u.t1 : null, dead ? u.x1 : null, dead ? u.y1 : null,
                u.hp ?? null, u.maxhp, u.end, dead ? u.by_kind ?? 'unknown' : null, u.by_team, u.by_name, u.by_pid, u.by_illusion, u.amb, u.kdt];
        }));
        const pos = [];
        for (const l of lines) if (l.k === 'pos') for (const [uid, x, y, hp] of l.u) pos.push([gameId, uid, l.t, x, y, hp]);
        ins('INSERT INTO unit_pos VALUES (?, ?, ?, ?, ?, ?)', pos);
        const hits = lines.filter(l => l.k === 'hit');
        ins('INSERT INTO unit_hit VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', hits.map(h => [gameId, h.t, h.ak, h.at, h.ap, h.an, h.tk, h.tt, h.tp, h.tn, h.dmg, h.inf]));
        db.prepare('INSERT INTO rp_game VALUES (?, ?, ?, ?, ?, ?, ?)').run(gameId, dem, bind(stat.size), stat.mtimeMs, until, units.length, hits.length);
        db.exec('COMMIT');
    } catch (e) {
        db.exec('ROLLBACK');
        throw e;
    }
    return { units: units.length, positions: store.db.prepare('SELECT count(*) AS n FROM unit_pos WHERE game_id = ?').get(gameId).n, hits: lines.filter(l => l.k === 'hit').length, end };
}

/** `hlog.js replay` for one .dem: its log (same basename, .log, or game.log beside a remote job's replay) is ingested, then the last game of it
 *  (or `game`) gets the replay's rows. Returns a line of what was written. */
function replayDem(store, dem, { game, until } = {}) {
    dem = path.resolve(dem);
    const log = dem.replace(/\.dem$/, '.log');
    if (!fs.existsSync(log)) throw new Error(`no log beside ${dem} (${path.basename(log)})`);
    store.ingest(log);
    const games = store.query('SELECT game_id, game FROM games WHERE file = ? ORDER BY game', log);
    const g = game === undefined ? games[games.length - 1] : games.find(r => r.game === Number(game));
    if (!g) throw new Error(`no game ${game ?? ''} in ${log}`);
    const lines = readReplay(dem, until);
    const st = fs.statSync(dem);
    const r = ingestReplay(store, g.game_id, dem, lines, st);
    return `${path.basename(dem)} game ${g.game}: ${r.units} units, ${r.positions} positions, ${r.hits} hits to ${r.end ? Math.round(r.end.t) : '?'} s`
        + `; ${r.end ? `${r.end.deathMatched} unit deaths matched to a combat log death entry (of ${r.end.deathEntries}, wards and summons among them)` : ''}`;
}

/** The .dem a `replay` argument names: a path to a .dem, a log (its sibling), or a run label of one log in the store. */
function demOf(store, arg, logOf) {
    if (/\.dem$/.test(arg)) return arg;
    const log = /\.log$/.test(arg) ? arg : logOf(store, arg);
    const dem = path.resolve(log).replace(/\.log$/, '.dem');
    if (!fs.existsSync(dem)) throw new Error(`no replay beside ${log} (${path.basename(dem)}): the game was not recorded`);
    return dem;
}

module.exports = { readReplay, ingestReplay, replayDem, demOf, EXE };
