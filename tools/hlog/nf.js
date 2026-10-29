// Noise floor over a dotactl batch manifest: dynamic metrics (dynamic.js) per game, then per seed and arm the mean, SD, n
// and the minimum detectable effect at N per arm. Also runs the slice-15 output gate on every game.
// Usage: node nf.js <manifest> [--n 5] [--json]
'use strict';

const fs = require('fs');
const { parseLog } = require('./parse');
const { laningMetrics } = require('./metrics');
const { dynamicMetrics, deathTimes, series } = require('./dynamic');
const { readManifest } = require('./manifest');

// Two-sided 0.05, power 0.8, two-sample t: (t_crit + t_power) * SD * sqrt(2 / N), df = 2N - 2.
const T975 = { 4: 2.776, 6: 2.447, 8: 2.306, 10: 2.228, 18: 2.101, 38: 2.024 };
const T80 = { 4: 0.941, 6: 0.906, 8: 0.889, 10: 0.879, 18: 0.862, 38: 0.851 };
function mde(sd, n) {
    if (!(sd > 0)) return NaN; // not estimable from a zero or missing SD
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
        // Slice 3 (H.2): both teams; undefined on logs without ev=creep_death.
        audited_steals: m.audited_steals && m.audited_steals.length,
        audited_steals_laning: m.audited_steals && m.audited_steals.filter(c => c.mode === 'laning').length,
        // Slice 3's bar: steals whose swing started in a mode Ours.LeaveCoreCreep owns.
        audited_steals_ours: m.audited_steals && m.audited_steals.filter(c => c.mode === 'laning' || c.mode === 'team_roam').length,
        idle_10s: m.idle_10s,
        lua_error: m.lua_error,
    };
    for (const r of [1, 2, 3, 4, 5]) out[`lh_at_10_pos${r}`] = ((m.lh_at_10[`r${r}`] ?? 0) + (m.lh_at_10[`d${r}`] ?? 0)) / 2;
    // Cores that never leave their lane are left out of the mean; nf.js gate reports them.
    const exits = ['r1', 'r3', 'd1', 'd3'].map(k => m.core_lane_exit_time[k]).filter(v => v !== undefined);
    out.core_lane_exit_time = exits.length ? exits.reduce((a, b) => a + b, 0) / exits.length : undefined;
    // Beside the role keys above: the same metrics by lineup position (ev=bot pos=), and how many slots the two disagree on.
    out.lua_error_ours = m.lua_error_ours;
    out.console_errors = m.console_errors;
    out.console_squelches = m.console_squelches;
    out.console_censored = m.console_censored ? 1 : 0;
    // No ?? 0 here: a team without trusted positions leaves the key undefined, which the gate reports as missing.
    for (const r of [1, 2, 3, 4, 5]) out[`lh_at_10_lpos${r}`] = (m.lh_at_10_lpos[`r${r}`] + m.lh_at_10_lpos[`d${r}`]) / 2;
    const lexits = ['r1', 'r3', 'd1', 'd3'].map(k => m.core_lane_exit_time_lpos[k]).filter(v => v !== undefined);
    out.core_lane_exit_time_lpos = lexits.length ? lexits.reduce((a, b) => a + b, 0) / lexits.length : undefined;
    out.role_mismatch = m.role_mismatch;
    return out;
}

/** Output gate for one game: deaths vs kills, lh_at_10 vs laningMetrics, missing metrics. Returns problem strings. */
function gate(game, m, flat) {
    const problems = [];
    // Deaths found by deathTimes (counter increments plus bots dead at the end) against hero kills on the scoreboard. Deaths to
    // towers, creeps and neutrals credit no kill, so deaths above kills are expected; the check flags a gap either way, and only
    // kills above deaths would suggest a missed death.
    let kills = 0;
    for (const b of Object.values(game.bots)) {
        const last = b.snaps.filter(s => typeof s.kills === 'number').pop();
        if (last) kills += last.kills;
    }
    const deaths = deathTimes(series(game)).length;
    if (deaths > 0 && Math.abs(kills - deaths) / deaths > 0.1) problems.push(`hero kills ${kills} vs deaths ${deaths} differ by > 10%`);
    const lane = Object.fromEntries(laningMetrics(game, { until: 600 }).bots.map(b => [b.pid, b]));
    for (const [role, pid] of Object.entries(m.pids)) {
        if (!lane[pid]) problems.push(`lh_at_10 ${role}: no laningMetrics row`);
        else if (lane[pid].lh !== m.lh_at_10[role]) problems.push(`lh_at_10 ${role}: ${m.lh_at_10[role]} vs laningMetrics ${lane[pid].lh}`);
    }
    if (m.bots !== 10) problems.push(`${m.bots} bots with snapshots`);
    for (const k of ['r1', 'r3', 'd1', 'd3']) if (m.core_lane_exit_time[k] === undefined) problems.push(`${k} never left lane`);
    problems.push(...m.warnings);
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

// t(0.975) for df 1-30 (standard tables).
const T975_TABLE = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.16, 2.145, 2.131,
    2.12, 2.11, 2.101, 2.093, 2.086, 2.08, 2.074, 2.069, 2.064, 2.06, 2.056, 2.052, 2.048, 2.045, 2.042];
/** Two-sided 0.05 t critical value for any df >= 1: the table, interpolated in 1/df for Welch's fractional df; above 30 a
 *  Cornish-Fisher expansion (within 0.001 there). */
function t975(df) {
    if (df < 30) {
        const lo = Math.max(1, Math.floor(df)), hi = lo + 1;
        const w = (1 / lo - 1 / df) / (1 / lo - 1 / hi);
        return T975_TABLE[lo - 1] + w * (T975_TABLE[hi - 1] - T975_TABLE[lo - 1]);
    }
    const z = 1.959964;
    return z + (z ** 3 + z) / (4 * df) + (5 * z ** 5 + 16 * z ** 3 + 3 * z) / (96 * df ** 2) +
        (3 * z ** 7 + 19 * z ** 5 + 17 * z ** 3 - 15 * z) / (384 * df ** 3);
}

/** ON - OFF for one seed: Welch 95% CI. Returns { delta, se, df, lo, hi }. */
function welch(off, on) {
    const vOff = off.sd ** 2 / off.n, vOn = on.sd ** 2 / on.n;
    const se = Math.sqrt(vOff + vOn);
    const delta = on.mean - off.mean;
    if (!(se > 0)) return { delta, se, df: NaN, lo: delta, hi: delta };
    const df = (vOff + vOn) ** 2 / (vOff ** 2 / (off.n - 1) + vOn ** 2 / (on.n - 1));
    const h = t975(df) * se;
    return { delta, se, df, lo: delta - h, hi: delta + h };
}

/** Seeds pooled with equal weight (a stratified mean of the per-seed deltas), Satterthwaite df. */
function pooled(perSeed) {
    const rows = perSeed.filter(r => Number.isFinite(r.delta) && Number.isFinite(r.se));
    const k = rows.length;
    if (!k) return { delta: NaN, se: NaN, df: NaN, lo: NaN, hi: NaN };
    const delta = rows.reduce((a, r) => a + r.delta, 0) / k;
    const v = rows.reduce((a, r) => a + r.se ** 2, 0);
    const se = Math.sqrt(v) / k;
    if (!(se > 0)) return { delta, se, df: NaN, lo: delta, hi: delta };
    const dfs = rows.filter(r => r.se > 0);
    const df = v ** 2 / dfs.reduce((a, r) => a + r.se ** 4 / r.df, 0);
    const h = t975(df) * se;
    return { delta, se, df, lo: delta - h, hi: delta + h };
}

/** One manifest game with its parsed game: the flat metrics and the gate's problems. */
function nfGame(g, game) {
    const m = dynamicMetrics(game);
    const flat = flatten(m);
    return { ...g, flat, problems: gate(game, m, flat), monitors: { first_t1_time: m.first_t1_time, first_roshan_time: m.first_roshan_time } };
}

/** Per metric, per seed and pooled ('all'): OFF and ON stats, the MDE at n per arm and seed, and the Welch delta. */
function noiseTable(games, n) {
    const groups = {};
    for (const g of games) (groups[`${g.seed}`] = groups[`${g.seed}`] || []).push(g);
    const table = {};
    for (const [seed, gs] of Object.entries(groups)) {
        for (const key of Object.keys(gs[0].flat)) {
            const off = stats(gs.filter(g => g.arm === 'off').map(g => g.flat[key]));
            const on = stats(gs.filter(g => g.arm === 'on').map(g => g.flat[key]));
            (table[key] = table[key] || {})[seed] = { off, on, mde: mde(off.sd, n), ...welch(off, on) };
        }
    }
    for (const bySeed of Object.values(table)) {
        const rows = Object.values(bySeed);
        // Pooled OFF SD: root mean square of the per-seed SDs (equal weights, as the pooled delta).
        const sds = rows.map(r => r.off.sd).filter(Number.isFinite);
        const sd = sds.length ? Math.sqrt(sds.reduce((a, s) => a + s * s, 0) / sds.length) : NaN;
        const off = stats(rows.map(r => r.off.mean)), on = stats(rows.map(r => r.on.mean));
        bySeed.all = { off: { n: rows.reduce((a, r) => a + r.off.n, 0), mean: off.mean, sd }, on: { n: rows.reduce((a, r) => a + r.on.n, 0), mean: on.mean },
            mde: mde(sd, n * rows.length), ...pooled(rows) };
    }
    return table;
}

function main(argv) {
    const file = argv[0];
    const n = Number((argv.join(' ').match(/--n (\d+)/) || [])[1] || 5);
    const games = readManifest(file).map(g => {
        const parsed = parseLog(fs.readFileSync(g.log, 'utf8'));
        return nfGame(g, parsed[parsed.length - 1]);
    });
    const groups = {};
    for (const g of games) (groups[`${g.seed}`] = groups[`${g.seed}`] || []).push(g);
    const table = noiseTable(games, n);
    if (argv.includes('--json')) {
        console.log(JSON.stringify({ games, table }, null, 1));
        return;
    }
    console.log('gate:');
    for (const g of games) console.log(`  ${g.label.padEnd(16)} ${g.problems.length ? g.problems.join('; ') : 'ok'}`);
    console.log('\nconsole censoring (Dota squelch notice seen; lua_error and console_errors means are then lower bounds):');
    for (const [seed, gs] of Object.entries(groups)) {
        for (const arm of ['off', 'on']) {
            const a = gs.filter(g => g.arm === arm);
            console.log(`  seed ${seed} ${arm}: ${a.filter(g => g.flat.console_censored).length}/${a.length} censored`);
        }
    }
    const f = x => (Number.isFinite(x) ? x.toFixed(1) : '-');
    console.log(`\nmetric | seed | OFF mean | OFF SD | n | MDE (N=${n} per seed) | ON mean | ON-OFF | 95% CI (Welch; all = seeds pooled)`);
    for (const [key, bySeed] of Object.entries(table)) {
        for (const [seed, r] of Object.entries(bySeed)) {
            console.log(`${key} | ${seed} | ${f(r.off.mean)} | ${f(r.off.sd)} | ${r.off.n} | ${f(r.mde)} | ${f(r.on.mean)} | ${f(r.delta)} | ${f(r.lo)} to ${f(r.hi)}`);
        }
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { flatten, gate, stats, mde, t975, welch, pooled, nfGame, noiseTable };
