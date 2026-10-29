// Where cores lose last hits (BACKLOG 1.12, WO-025) from ev=creep_death: per core (lineup position 1-3), the enemy lane
// creeps that died near it, who got them, and what the core was doing. Also the WO-025 telemetry gates G1-G6: a game that
// fails G2-G6 is left out of the summary, and so is a core that fails G1. The counting is the named queries `@lasthit_cores`
// and `@lasthit_gates` (queries/); this file holds the gate thresholds, the per-position summary and the printing.
// Usage: node lasthit_cause.js <manifest | log...> [--until 600] [--json]
'use strict';

const fs = require('fs');
const path = require('path');
const { parseLog } = require('./parse');

// WO-025 (`judgement`): a death counts for a core within R; "late" if its own attack on the creep started under LATE_S
// before the death; "idle in range" if within its attack range + REACH and not attacking the creep. The values are in
// queries/lasthit_cores.sql (1000, 0.6, 300), kept here for the --json output.
const C = { R: 1000, LATE_S: 0.6, REACH: 300 };
// WO-025 gates (`judgement`): G1 attributed share of a core's own last hits; G2 revived share of deaths (fog deaths);
// G4 attributed share of the other team's denies; G5 share of a core's own last hits it was attacking (handle identity and
// clock), with no negative attack age; G6 deaths per team, against EC-004's ~76-84 lane creeps per lane by 10:00.
const GATE = { G1: 0.9, G2: 0.05, G4: 0.5, G4_MIN: 5, G5: 0.8, G6: 270 };
const KILLERS = ['core_lh', 'ally_lh', 'enemy_deny', 'creep_or_tower'];
const STATES = ['late', 'early', 'idle_in_range', 'away'];

/**
 * One game's cores and gates from the log store: `store` holds the log (Store.ingestAll), `file` is its path as in games.file.
 * Returns { cores: { r1..r3, d1..d3 }, gates, failed, keep } (the shape lasthit_cause.js had before it moved into SQL).
 */
function lasthitCause(store, file, game = 1, until = 600) {
    if (!store.query('SELECT 1 FROM games WHERE file = ? AND game = ?', file, game).length) {
        throw new Error(`lasthitCause: ${file} game ${game} is not in the store (the path must be absolute, as in games.file; ingest it first)`);
    }
    const p = { file, game, until };
    const cores = {};
    for (const r of store.query(fs.readFileSync(path.join(__dirname, 'queries', 'lasthit_cores.sql'), 'utf8'), p)) {
        const o = {
            pid: r.pid, team: r.team, pos: r.pos, hero: r.hero ?? undefined, lane: r.lane ?? undefined, near: r.near,
            laneDeaths: r.lane_deaths, absent: r.absent,
            killers: { core_lh: r.core_lh, ally_lh: r.ally_lh, enemy_deny: r.enemy_deny, creep_or_tower: r.creep_or_tower },
            states: { late: r.late, early: r.early, idle_in_range: r.idle_in_range, away: r.away },
            lh: r.lh, attributed: r.attributed,
        };
        o.conversion = o.near ? o.killers.core_lh / o.near : undefined;
        cores[`${r.team === 2 ? 'r' : 'd'}${r.pos}`] = o;
    }
    const q = store.query(fs.readFileSync(path.join(__dirname, 'queries', 'lasthit_gates.sql'), 'utf8'), p)[0];
    const G4 = {
        2: q.dn_d >= GATE.G4_MIN ? q.deny_r / q.dn_d : undefined,
        3: q.dn_r >= GATE.G4_MIN ? q.deny_d / q.dn_r : undefined,
    };
    const gates = {
        G1: Object.fromEntries(Object.entries(cores).map(([k, r]) => [k, r.lh ? r.attributed / r.lh : undefined])),
        G2: q.deaths ? q.revives / q.deaths : 0,
        G3: q.telemetry_errors,
        G4,
        G5: { share: q.own ? q.on_it / q.own : undefined, negA: q.neg_a },
        G6: Math.max(0, q.deaths_r, q.deaths_d),
    };
    const failed = [];
    if (gates.G2 >= GATE.G2) failed.push('G2');
    if (gates.G3 > 0) failed.push('G3');
    if (Object.values(G4).some(v => v !== undefined && v < GATE.G4)) failed.push('G4');
    if (q.neg_a > 0 || (q.own && q.on_it / q.own < GATE.G5)) failed.push('G5');
    if (gates.G6 > GATE.G6) failed.push('G6');
    for (const [k, r] of Object.entries(cores)) r.keep = r.lh > 0 && gates.G1[k] >= GATE.G1;
    return { cores, gates, failed, keep: failed.length === 0 };
}

const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
const sd = a => (a.length > 1 ? Math.sqrt(a.reduce((x, y) => x + (y - mean(a)) ** 2, 0) / (a.length - 1)) : 0);

/** Per position over games: share of near deaths per killer and per core state, and conversion (mean and SD). */
function summarise(results) {
    const out = {};
    for (const pos of [1, 2, 3]) {
        const rs = results.filter(g => g.keep).flatMap(g => ['r', 'd'].map(s => g.cores[`${s}${pos}`]).filter(r => r && r.keep && r.near > 0));
        if (!rs.length) continue;
        const share = f => rs.map(r => f(r) / r.near);
        const row = { n: rs.length, conversion: [mean(share(r => r.killers.core_lh)), sd(share(r => r.killers.core_lh))] };
        for (const k of KILLERS) row[k] = [mean(share(r => r.killers[k])), sd(share(r => r.killers[k]))];
        for (const k of STATES) row[`lost_${k}`] = [mean(share(r => r.states[k])), sd(share(r => r.states[k]))];
        row.absent_of_lane = [mean(rs.map(r => (r.laneDeaths ? r.absent / r.laneDeaths : 0))), sd(rs.map(r => (r.laneDeaths ? r.absent / r.laneDeaths : 0)))];
        row.lh = [mean(rs.map(r => r.lh)), sd(rs.map(r => r.lh))];
        out[`pos${pos}`] = row;
    }
    return out;
}

function logsFrom(args) {
    if (args.length === 1 && /\.manifest$/.test(args[0])) {
        return fs.readFileSync(args[0], 'utf8').split('\n').filter(l => /status=ok/.test(l)).map(l => l.match(/log="([^"]+)"/)[1]);
    }
    return args;
}

/** [file, game] per log; logs with no game (the think-rate runs share the b25 manifest) are skipped. */
function gamesFrom(files) {
    return files.map(f => [f, parseLog(fs.readFileSync(f, 'utf8'))[0]]).filter(([, g]) => g && Object.keys(g.bots).length);
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node lasthit_cause.js <manifest | log...> [--until 600] [--json]');
        process.exit(2);
    }
    const until = Number(opt('until') ?? 600);
    const { Store, DB } = require('./store'); // here, so steals.js (gamesFrom, logsFrom) does not load SQLite
    const store = new Store(DB);
    for (const f of store.ingestAll(files).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const results = files.map(f => path.resolve(f))
        .filter(f => store.query('SELECT 1 FROM games g WHERE g.file = ? AND g.game = 1 AND EXISTS (SELECT 1 FROM ev_bot b WHERE b.game_id = g.game_id)', f).length)
        .map(f => ({ file: f, ...lasthitCause(store, f, 1, until) }));
    const summary = summarise(results);
    if (argv.includes('--json')) return console.log(JSON.stringify({ C, until, results, summary }, null, 1));
    for (const g of results) console.log(`${g.file}
  ${g.keep ? 'kept' : 'DROPPED ' + g.failed.join(',')} gates ${JSON.stringify(g.gates)}`);
    const pct = ([m, s]) => `${(100 * m).toFixed(0)}% (${(100 * s).toFixed(0)})`;
    for (const [pos, row] of Object.entries(summary)) {
        console.log(`${pos} n=${row.n} lh@${until / 60} ${row.lh[0].toFixed(1)} conversion ${pct(row.conversion)} absent-of-lane ${pct(row.absent_of_lane)}`);
        console.log('  killers ' + KILLERS.map(k => `${k} ${pct(row[k])}`).join(', '));
        console.log('  core when lost ' + STATES.map(k => `${k} ${pct(row[`lost_${k}`])}`).join(', '));
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { lasthitCause, summarise, gamesFrom, logsFrom, C, GATE };
