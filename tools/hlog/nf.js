// Noise floor over a dotactl batch manifest: dynamic metrics (dynamic.js) per game, then per seed and arm the mean, SD, n
// and the minimum detectable effect at N per arm. Also runs the slice-15 output gate on every game.
// Usage: node nf.js <manifest> [--n 5] [--json]
'use strict';

const fs = require('fs');
const { parseLog } = require('./parse');
const { laningMetrics } = require('./metrics');
const { dynamicMetrics } = require('./dynamic');

// Two-sided 0.05, power 0.8, two-sample t: (t_crit + t_power) * SD * sqrt(2 / N), df = 2N - 2.
const T975 = { 4: 2.776, 6: 2.447, 8: 2.306, 10: 2.228, 18: 2.101, 38: 2.024 };
const T80 = { 4: 0.941, 6: 0.906, 8: 0.889, 10: 0.879, 18: 0.862, 38: 0.851 };
function mde(sd, n) {
    const df = 2 * n - 2;
    const k = Object.keys(T975).map(Number).reduce((a, b) => (Math.abs(b - df) < Math.abs(a - df) ? b : a));
    return (T975[k] + T80[k]) * sd * Math.sqrt(2 / n);
}

/** Scalar metrics for the noise floor (per-team values summed over both teams unless the key says otherwise). */
function flatten(m) {
    const both = o => (o[2] ?? 0) + (o[3] ?? 0);
    const out = {
        encounters_before10: m.encounters_per_10min.before10,
        encounters_per_10min_after10: m.encounters_per_10min.after10,
        fights_before10: m.fights_per_10min.before10,
        fights_per_10min_after10: m.fights_per_10min.after10,
        deaths_before_10: both(m.deaths_before_10),
        rotation_attempts_10: both(m.rotation_attempts_per_team_10),
        tp_joins: both(m.tp_joins_per_team),
        ally_creep_steals: both(m.ally_creep_steals),
        idle_10s: m.idle_10s,
        lua_error: m.lua_error,
    };
    for (const r of [1, 2, 3, 4, 5]) out[`lh_at_10_pos${r}`] = ((m.lh_at_10[`r${r}`] ?? 0) + (m.lh_at_10[`d${r}`] ?? 0)) / 2;
    const exits = ['r1', 'r3', 'd1', 'd3'].map(k => m.core_lane_exit_time[k]).filter(v => v !== undefined);
    out.core_lane_exit_time = exits.length ? exits.reduce((a, b) => a + b, 0) / exits.length : undefined;
    return out;
}

/** Output gate for one game: deaths vs kills, lh_at_10 vs laningMetrics, missing metrics. Returns problem strings. */
function gate(game, m, flat) {
    const problems = [];
    let kills = 0, deaths = 0;
    for (const b of Object.values(game.bots)) {
        const last = b.snaps.filter(s => typeof s.deaths === 'number').pop();
        if (last) [kills, deaths] = [kills + (last.kills || 0), deaths + last.deaths];
    }
    if (deaths > 0 && Math.abs(kills - deaths) / deaths > 0.1) problems.push(`hero kills ${kills} vs deaths ${deaths} differ by > 10%`);
    const lane = laningMetrics(game, { until: 600 });
    for (const [role, pid] of Object.entries(m.pids)) {
        if (lane[pid] && lane[pid].lh !== m.lh_at_10[role]) problems.push(`lh_at_10 ${role}: ${m.lh_at_10[role]} vs laningMetrics ${lane[pid].lh}`);
    }
    if (m.bots !== 10) problems.push(`${m.bots} bots with snapshots`);
    for (const [k, v] of Object.entries(flat)) if (v === undefined || Number.isNaN(v)) problems.push(`${k} missing`);
    return problems;
}

function stats(xs) {
    const v = xs.filter(x => typeof x === 'number');
    const n = v.length;
    const mean = n ? v.reduce((a, b) => a + b, 0) / n : NaN;
    const sd = n > 1 ? Math.sqrt(v.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1)) : NaN;
    return { n, mean, sd };
}

function readManifest(file) {
    return fs
        .readFileSync(file, 'utf8')
        .split(/\r?\n/)
        .filter(l => /status=ok/.test(l))
        .map(l => ({
            label: l.match(/label="([^"]*)"/)[1],
            seed: Number(l.match(/seed=(\d+)/)[1]),
            arm: l.match(/arm=(\w+)/)[1],
            log: l.match(/log="([^"]*)"/)[1],
        }));
}

function main(argv) {
    const file = argv[0];
    const n = Number((argv.join(' ').match(/--n (\d+)/) || [])[1] || 5);
    const games = [];
    for (const g of readManifest(file)) {
        const parsed = parseLog(fs.readFileSync(g.log, 'utf8'));
        const game = parsed[parsed.length - 1];
        const m = dynamicMetrics(game);
        const flat = flatten(m);
        games.push({ ...g, flat, problems: gate(game, m, flat) });
    }
    const groups = {};
    for (const g of games) (groups[`${g.seed}`] = groups[`${g.seed}`] || []).push(g);
    const table = {};
    for (const [seed, gs] of Object.entries(groups)) {
        for (const key of Object.keys(gs[0].flat)) {
            const off = stats(gs.filter(g => g.arm === 'off').map(g => g.flat[key]));
            const on = stats(gs.filter(g => g.arm === 'on').map(g => g.flat[key]));
            (table[key] = table[key] || {})[seed] = { off, on, mde: mde(off.sd, n), delta: on.mean - off.mean };
        }
    }
    if (argv.includes('--json')) {
        console.log(JSON.stringify({ games, table }, null, 1));
        return;
    }
    console.log('gate:');
    for (const g of games) console.log(`  ${g.label.padEnd(16)} ${g.problems.length ? g.problems.join('; ') : 'ok'}`);
    const f = x => (Number.isFinite(x) ? x.toFixed(1) : '-');
    console.log(`\nmetric | seed | OFF mean | OFF SD | n | MDE (N=${n}) | ON mean | ON-OFF (exploratory)`);
    for (const [key, bySeed] of Object.entries(table)) {
        for (const [seed, r] of Object.entries(bySeed)) {
            console.log(`${key} | ${seed} | ${f(r.off.mean)} | ${f(r.off.sd)} | ${r.off.n} | ${f(r.mde)} | ${f(r.on.mean)} | ${f(r.delta)}`);
        }
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { flatten, gate, stats, mde };
