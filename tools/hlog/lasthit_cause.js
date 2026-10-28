// Where cores lose last hits (BACKLOG 1.12, WO-025) from ev=creep_death: per core (lineup position 1-3), the enemy lane
// creeps that died near it, who got them, and what the core was doing. Also the G1/G2 telemetry gates of WO-025.
// Usage: node lasthit_cause.js <manifest | log...> [--until 600] [--json]
'use strict';

const fs = require('fs');
const { parseLog } = require('./parse');
const { series, laneLabel } = require('./dynamic');

// WO-025 (`judgement`): a death counts for a core within R; "late" if its own attack on the creep started under LATE_S
// before the death; "idle in range" if within its attack range + REACH and not attacking the creep.
const C = { R: 1000, LATE_S: 0.6, REACH: 300 };
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
    if (typeof a === 'number') return a >= C.LATE_S ? 'early' : 'late';
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
            const r = { pid: me, hero: S[me].hero, lane, near: 0, laneDeaths: 0, absent: 0, killers: {}, states: {} };
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
    return {
        cores: out,
        gates: {
            G1: Object.fromEntries(Object.entries(out).map(([k, r]) => [k, r.lh ? r.attributed / r.lh : undefined])),
            G2: all ? deaths.filter(e => e.hp > 0.5).length / all : 0,
            G3: game.events.filter(e => e.ev === 'lua_error' && /^Telemetry/.test(String(e.where))).length,
        },
    };
}

const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
const sd = a => (a.length > 1 ? Math.sqrt(a.reduce((x, y) => x + (y - mean(a)) ** 2, 0) / (a.length - 1)) : 0);

/** Per position over games: share of near deaths per killer and per core state, and conversion (mean and SD). */
function summarise(results) {
    const out = {};
    for (const pos of [1, 2, 3]) {
        const rs = results.flatMap(g => ['r', 'd'].map(s => g.cores[`${s}${pos}`]).filter(r => r && r.near > 0));
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

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node lasthit_cause.js <manifest | log...> [--until 600] [--json]');
        process.exit(2);
    }
    const until = Number(opt('until') ?? 600);
    const results = files.map(f => ({ file: f, ...lasthitCause(parseLog(fs.readFileSync(f, 'utf8'))[0], until) }));
    const summary = summarise(results);
    if (argv.includes('--json')) return console.log(JSON.stringify({ C, until, results, summary }, null, 1));
    for (const g of results) console.log(`${g.file}\n  gates ${JSON.stringify(g.gates)}`);
    const pct = ([m, s]) => `${(100 * m).toFixed(0)}% (${(100 * s).toFixed(0)})`;
    for (const [pos, row] of Object.entries(summary)) {
        console.log(`${pos} n=${row.n} lh@${until / 60} ${row.lh[0].toFixed(1)} conversion ${pct(row.conversion)} absent-of-lane ${pct(row.absent_of_lane)}`);
        console.log('  killers ' + KILLERS.map(k => `${k} ${pct(row[k])}`).join(', '));
        console.log('  core when lost ' + STATES.map(k => `${k} ${pct(row[`lost_${k}`])}`).join(', '));
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { lasthitCause, summarise, coreState, C };
