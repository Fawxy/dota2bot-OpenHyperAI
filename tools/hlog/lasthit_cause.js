// Where cores lose last hits (BACKLOG 1.12, WO-025) from ev=creep_death: per core (lineup position 1-3), the enemy lane
// creeps that died near it, who got them, and what the core was doing. Also the WO-025 telemetry gates G1-G6: a game that
// fails G2-G6 is left out of the summary, and so is a core that fails G1.
// Usage: node lasthit_cause.js <manifest | log...> [--until 600] [--json]
'use strict';

const fs = require('fs');
const { parseLog } = require('./parse');
const { series, laneLabel } = require('./dynamic');

// WO-025 (`judgement`): a death counts for a core within R; "late" if its own attack on the creep started under LATE_S
// before the death; "idle in range" if within its attack range + REACH and not attacking the creep.
const C = { R: 1000, LATE_S: 0.6, REACH: 300 };
// WO-025 gates (`judgement`): G1 attributed share of a core's own last hits; G2 revived share of deaths (fog deaths);
// G4 attributed share of the other team's denies; G5 share of a core's own last hits it was attacking (handle identity and
// clock), with no negative attack age; G6 deaths per team, against EC-004's ~76-84 lane creeps per lane by 10:00.
const GATE = { G1: 0.9, G2: 0.05, G4: 0.5, G4_MIN: 5, G5: 0.8, A_MAX: 2, G6: 270 };
const KILLERS = ['core_lh', 'ally_lh', 'enemy_deny', 'creep_or_tower'];
const STATES = ['late', 'early', 'idle_in_range', 'away'];

/** Lineup position per pid from the last ev=bot pos= (as dynamic.js lpos). */
function positions(game) {
    const out = {};
    for (const b of Object.values(game.bots)) {
        const p = (b.profiles || []).filter(e => typeof e.pos === 'number').pop();
        if (p && b.team !== undefined) out[`${b.team}:${p.pos}`] = b.pid;
    }
    return out;
}

/** Modal lane of a bot's snapshots in [a, b) s, ignoring base/other. */
function homeLane(s, a, b) {
    const n = {};
    for (const snap of s.snaps) {
        if (snap.t < a || snap.t >= b || snap.alive === 0) continue;
        const L = laneLabel([snap.x, snap.y]);
        if (L !== 'base' && L !== 'other') n[L] = (n[L] || 0) + 1;
    }
    return Object.entries(n).sort((x, y) => y[1] - x[1])[0]?.[0];
}

/** What the core was doing when a creep it did not get died within R of it. */
function coreState(e, pos) {
    const a = e[`p${pos}a`], t = e[`p${pos}t`];
    if (typeof a === 'number' && a >= 0) return a >= C.LATE_S ? 'early' : 'late';
    if (t === 1 || t === true) return 'late';
    return e[`p${pos}d`] <= (e[`p${pos}r`] ?? 150) + C.REACH ? 'idle_in_range' : 'away';
}

function lasthitCause(game, until = 600) {
    const S = series(game);
    const pid = positions(game);
    const deaths = game.events.filter(e => e.ev === 'creep_death' && e.t < until);
    const out = {};
    for (const team of [2, 3]) {
        for (const pos of [1, 2, 3]) {
            const me = pid[`${team}:${pos}`];
            if (me === undefined || !S[me]) continue;
            const lane = homeLane(S[me], 60, until);
            const r = { pid: me, team, pos, hero: S[me].hero, lane, near: 0, laneDeaths: 0, absent: 0, killers: {}, states: {} };
            KILLERS.forEach(k => (r.killers[k] = 0));
            STATES.forEach(k => (r.states[k] = 0));
            for (const e of deaths) {
                if (e.team !== team) continue;
                const d = e[`p${pos}d`];
                const near = typeof d === 'number' && d <= C.R;
                const inLane = lane !== undefined && laneLabel([e.x, e.y]) === lane;
                if (inLane) r.laneDeaths++;
                if (!near) {
                    if (inLane) r.absent++;
                    continue;
                }
                r.near++;
                const by = e.by;
                const killer = by === me ? 'core_lh' : by === 'deny' ? 'enemy_deny' : by === 'none' || by === undefined ? 'creep_or_tower' : 'ally_lh';
                r.killers[killer]++;
                if (killer !== 'core_lh') r.states[coreState(e, pos)]++;
            }
            r.conversion = r.near ? r.killers.core_lh / r.near : undefined;
            // G1: attributed last hits against the core's own counter.
            const snaps = S[me].snaps.filter(s => s.t <= until && typeof s.lh === 'number');
            r.lh = snaps.length ? snaps[snaps.length - 1].lh : 0;
            r.attributed = deaths.filter(e => e.by === me).length;
            out[`${team === 2 ? 'r' : 'd'}${pos}`] = r;
        }
    }
    const all = deaths.length;
    const revives = game.events.filter(e => e.ev === 'creep_revive' && e.t < until).length;
    // G4: per team, denies attributed on its deaths against the other team's own deny counter.
    const G4 = {};
    for (const team of [2, 3]) {
        const dn = Object.values(S).filter(b => b.team === 5 - team).reduce((n, b) => n + lastAt(b, 'dn', until), 0);
        G4[team] = dn >= GATE.G4_MIN ? deaths.filter(e => e.team === team && e.by === 'deny').length / dn : undefined;
    }
    // G5: a core's own last hits should be on the creep it was attacking.
    let own = 0, onIt = 0, negA = 0;
    for (const e of deaths) {
        for (const pos of [1, 2, 3]) if (typeof e[`p${pos}a`] === 'number' && e[`p${pos}a`] < 0) negA++;
        const r = Object.values(out).find(x => x.pid === e.by && x.team === e.team);
        if (!r || e[`p${r.pos}d`] === undefined) continue;
        own++;
        const a = e[`p${r.pos}a`], t = e[`p${r.pos}t`];
        if (t === 1 || t === true || (typeof a === 'number' && a >= 0 && a <= GATE.A_MAX)) onIt++;
    }
    const G6 = Math.max(0, ...[2, 3].map(team => deaths.filter(e => e.team === team).length));
    const gates = {
        G1: Object.fromEntries(Object.entries(out).map(([k, r]) => [k, r.lh ? r.attributed / r.lh : undefined])),
        G2: all ? revives / all : 0,
        G3: game.events.filter(e => e.ev === 'lua_error' && /^Telemetry/.test(String(e.where))).length,
        G4,
        G5: { share: own ? onIt / own : undefined, negA },
        G6,
    };
    const failed = [];
    if (gates.G2 >= GATE.G2) failed.push('G2');
    if (gates.G3 > 0) failed.push('G3');
    if (Object.values(G4).some(v => v !== undefined && v < GATE.G4)) failed.push('G4');
    if (negA > 0 || (own && onIt / own < GATE.G5)) failed.push('G5');
    if (G6 > GATE.G6) failed.push('G6');
    for (const [k, r] of Object.entries(out)) r.keep = r.lh > 0 && gates.G1[k] >= GATE.G1;
    return { cores: out, gates, failed, keep: failed.length === 0 };
}

/** Last value of a snapshot counter at or before until (0 if none). */
function lastAt(b, key, until) {
    const v = b.snaps.filter(s => s.t <= until && typeof s[key] === 'number');
    return v.length ? v[v.length - 1][key] : 0;
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
    const games = gamesFrom(files);
    const results = games.map(([f, g]) => ({ file: f, ...lasthitCause(g, until) }));
    const summary = summarise(results);
    if (argv.includes('--json')) return console.log(JSON.stringify({ C, until, results, summary }, null, 1));
    for (const g of results) console.log(`${g.file}\n  ${g.keep ? 'kept' : 'DROPPED ' + g.failed.join(',')} gates ${JSON.stringify(g.gates)}`);
    const pct = ([m, s]) => `${(100 * m).toFixed(0)}% (${(100 * s).toFixed(0)})`;
    for (const [pos, row] of Object.entries(summary)) {
        console.log(`${pos} n=${row.n} lh@${until / 60} ${row.lh[0].toFixed(1)} conversion ${pct(row.conversion)} absent-of-lane ${pct(row.absent_of_lane)}`);
        console.log('  killers ' + KILLERS.map(k => `${k} ${pct(row[k])}`).join(', '));
        console.log('  core when lost ' + STATES.map(k => `${k} ${pct(row[`lost_${k}`])}`).join(', '));
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { lasthitCause, summarise, coreState, gamesFrom, C, GATE };
