// Audited steals (slice 3, KR H.2): every lane creep an own support (pos4/pos5) last-hit before --until while an own core
// could take it (queries/steals.sql), one line per case with the support's mode and the cores that could take it,
// so each remaining case can be judged a bug or a metric false positive.
// Usage: node steals.js <manifest | log...> [--until 600] [--json]
'use strict';

const fs = require('fs');
const path = require('path');
const { logsFrom } = require('./lasthit_cause');

const QUERY = fs.readFileSync(path.join(__dirname, 'queries/steals.sql'), 'utf8');
const clock = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
const AUDIT_BUF = 150; // the SQL's constant (dynamic.js C.AUDIT_BUF), for the cores listed per case

/** Cases of one logged game from the store: [{ t, team, pid, pos, mode, snapMode, swing, kind, cores }], undefined when the game
 *  has no ev=creep_death or no trusted lineup positions (the log cannot be audited). `file` is absolute, as in games.file. */
function stealsFor(store, file, game = 1, until = 600) {
    if (!store.query('SELECT 1 FROM games WHERE file = ? AND game = ?', file, game).length) {
        throw new Error(`${file} game ${game} is not in the store (the path must be absolute, as in games.file; ingest it first)`);
    }
    const rows = store.query(QUERY, { file, game, until }).map(r => ({ ...r }));
    const g = rows.find(r => r.kind === 'game');
    if (!g || !g.deaths || !g.lined) return undefined;
    return rows.filter(r => r.kind === 'case').map(r => {
        const cores = [1, 2, 3]
            .map(n => ({ core: n, d: r[`c${n}d`] ?? undefined, r: r[`c${n}r`] ?? undefined, attacking: r[`c${n}t`] === 1 }))
            .filter(c => c.d !== undefined && (c.attacking || c.d <= c.r + AUDIT_BUF));
        return { t: r.t, team: r.team, pid: r.pid, pos: r.pos, mode: r.mode ?? undefined, snapMode: r.snap_mode ?? undefined, swing: r.swing ?? undefined, kind: r.creep_kind, cores };
    });
}

/** Per log: { file, cases } (cases undefined for a log that cannot be audited). */
function steals(store, files, until) {
    return files.map(f => path.resolve(f))
        .filter(f => store.query('SELECT 1 FROM games g WHERE g.file = ? AND g.game = 1 AND EXISTS (SELECT 1 FROM ev_bot b WHERE b.game_id = g.game_id)', f).length)
        .map(file => ({ file, cases: stealsFor(store, file, 1, until) }));
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node steals.js <manifest | log...> [--until 600] [--json]');
        process.exit(2);
    }
    const { Store, DB } = require('./store');
    const store = new Store(DB);
    for (const f of store.ingestAll(files).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const out = steals(store, files, Number(opt('until') ?? 600));
    if (argv.includes('--json')) return console.log(JSON.stringify(out, null, 1));
    for (const g of out) {
        if (!g.cases) {
            console.log(`${g.file}\n  no ev=creep_death or lineup positions`);
            continue;
        }
        const laning = g.cases.filter(c => c.mode === 'laning').length;
        const ours = g.cases.filter(c => c.mode === 'laning' || c.mode === 'team_roam').length;
        console.log(`${g.file}\n  audited_steals ${g.cases.length} (laning ${laning}, laning or team_roam ${ours})`);
        for (const c of g.cases) {
            const cores = c.cores.map(k => `p${k.core} ${k.attacking ? 'attacking' : `d=${k.d} r=${k.r}`}`).join(', ');
            console.log(`  ${clock(c.t)} t=${c.t} team=${c.team} pid=${c.pid} pos${c.pos} mode=${c.mode}${c.swing !== undefined ? ` swing=${c.swing.toFixed(2)}s` : ''}${c.snapMode !== c.mode ? ` (snap ${c.snapMode})` : ''} ${c.kind} | ${cores}`);
        }
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { steals, stealsFor };
