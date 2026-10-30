// Noise floor over a dotactl batch manifest: dynamic metrics (dynamic.js) per game, then per seed and arm the mean, SD, n
// and the minimum detectable effect at N per arm. Also runs the slice-15 output gate on every game.
// Usage: node nf.js <manifest> [--n 5] [--json]
'use strict';

const fs = require('fs');
const path = require('path');
const { parseLog } = require('./parse');
const { laningMetrics } = require('./metrics');
const { dynamicMetrics } = require('./dynamic');
const { readManifest } = require('./manifest');
const { Store, DB } = require('./store');

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
        // Slice 4 (S.2a): attempts are started jobs; skips are trigger minutes with none. 0 in a game without ev=stack.
        stack_attempts: m.stacks.filter(s => s.res !== 'skip').length,
        stack_stacked: m.stacks.filter(s => s.res === 'stacked').length,
        // Slice 4 Amendment 1 (user 30/10/2026): the rate's denominator leaves out jobs OHA took over or the job's own stop on
        // hero damage; execution failures (missed, no-camp, stalled) stay in.
        stack_clean: m.stacks.filter(s => s.res !== 'skip' && !stackInterrupted(s)).length,
        stack_interrupted: m.stacks.filter(s => s.res !== 'skip' && stackInterrupted(s)).length,
        stack_deaths: m.stacks.filter(s => s.death).length,
        stack_away_max: Math.max(0, ...m.stacks.filter(s => s.res !== 'skip').map(s => s.away)),
        stack_skips: m.stacks.filter(s => s.res === 'skip').length,
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
    const deaths = m.deaths_total;
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

/** ln Gamma (Lanczos, g = 7): accurate to about 1e-14 for x > 0. */
function lnGamma(x) {
    const c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
        12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7];
    if (x < 0.5) return Math.log(Math.PI / Math.sin(Math.PI * x)) - lnGamma(1 - x);
    x -= 1;
    let a = c[0];
    const t = x + 7.5;
    for (let i = 1; i < 9; i++) a += c[i] / (x + i);
    return 0.5 * Math.log(2 * Math.PI) + (x + 0.5) * Math.log(t) - t + Math.log(a);
}

/** Regularised incomplete beta I_x(a, b) by its continued fraction (Numerical Recipes betacf). */
function betaInc(x, a, b) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const front = Math.exp(lnGamma(a + b) - lnGamma(a) - lnGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
    if (x > (a + 1) / (a + b + 2)) return 1 - betaInc(1 - x, b, a);
    let f = 1, c = 1, d = 1 - ((a + b) * x) / (a + 1);
    d = 1 / (Math.abs(d) < 1e-300 ? 1e-300 : d);
    f = d;
    for (let m = 1; m <= 200; m++) {
        for (const num of [(m * (b - m) * x) / ((a + 2 * m - 1) * (a + 2 * m)), -((a + m) * (a + b + m) * x) / ((a + 2 * m) * (a + 2 * m + 1))]) {
            d = 1 + num * d;
            d = 1 / (Math.abs(d) < 1e-300 ? 1e-300 : d);
            c = 1 + num / c;
            if (Math.abs(c) < 1e-300) c = 1e-300;
            f *= c * d;
        }
        if (Math.abs(c * d - 1) < 1e-12) break;
    }
    return (front * f) / a;
}

/** Two-sided t critical value at `alpha` for any df > 0 (P(|T| > t) = alpha), by bisection on the exact t CDF. Used for
 *  look-adjusted CIs (an interim look spends part of the alpha, e.g. 0.025 per look; skill eval-run rule 4). */
function tCrit(alpha, df) {
    const tail = t => 0.5 * betaInc(df / (df + t * t), df / 2, 0.5); // P(T > t)
    let lo = 0, hi = 1;
    while (tail(hi) > alpha / 2) hi *= 2;
    for (let i = 0; i < 100; i++) {
        const mid = (lo + hi) / 2;
        if (tail(mid) > alpha / 2) lo = mid; else hi = mid;
    }
    return (lo + hi) / 2;
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

/**
 * ON - OFF over all pairs with the lineup seed as a stratum: each seed's delta weighted by n_off*n_on/(n_off+n_on) (equal
 * weights when the arms are balanced), SE from the residual variance pooled over every seed and arm, df = N - 2 per seed.
 * A seed with one game per arm still counts in the delta (it adds no df); a seed with a game in one arm only is left out.
 * Assumes one variance across arms and seeds (the pooled-variance t); Welch per seed needed n >= 2 per arm and dropped the
 * rest (ROADMAP debt `cause: eval-cost`). `strata`: [{ off: [values], on: [values] }].
 */
function stratified(strata) {
    let sw = 0, swd = 0, ss = 0, df = 0;
    for (const s of strata) {
        const off = s.off.filter(Number.isFinite), on = s.on.filter(Number.isFinite);
        if (!off.length || !on.length) continue;
        const a = stats(off), b = stats(on);
        const w = (off.length * on.length) / (off.length + on.length);
        sw += w;
        swd += w * (b.mean - a.mean);
        for (const [xs, m] of [[off, a.mean], [on, b.mean]]) ss += xs.reduce((t, x) => t + (x - m) ** 2, 0);
        df += off.length + on.length - 2;
    }
    if (!sw) return { delta: NaN, se: NaN, df: NaN, lo: NaN, hi: NaN };
    const delta = swd / sw;
    if (!df) return { delta, se: NaN, df: NaN, lo: NaN, hi: NaN };
    const se = Math.sqrt(ss / df / sw);
    if (!(se > 0)) return { delta, se, df, lo: delta, hi: delta };
    const h = t975(df) * se;
    return { delta, se, df, lo: delta - h, hi: delta + h };
}

/** The log store (default file, or `db`) with a manifest's logs ingested; a log that fails to ingest is reported. */
function storeFor(manifest, db = DB) {
    const store = new Store(db);
    for (const f of store.ingestAll([manifest]).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    return store;
}

/** A started stack job that ended because OHA took the bot (`preempted:mode=*`, `preempted:never_started`, OHA's farm abort
 *  `cancelled:<why>`) or the job stopped on hero damage (`cancelled:hit`): not an execution outcome (slice 4 Amendment 1). */
function stackInterrupted(s) {
    const why = String(s.why ?? '');
    return why.startsWith('cancelled:') || why.startsWith('preempted:mode=') || why === 'preempted:never_started';
}

const QUERIES = path.join(__dirname, 'queries');

/**
 * Slice 5 (L.1) keys per lineup core position N (1-3), the mean of the two teams' posN at 10:00 (undefined when a team has no
 * such core): `conv_lposN` its own last hits over the enemy lane creeps that died within 1000 of it (@lasthit_cores core_lh /
 * near), and `dn_`, `lvl_`, `hph_at_10_lposN` from @core_costs. Conversion per team too (`conv_lposN_r`, `_d`): in OFF one
 * team's cores run OHA's last hits and the other Valve's, so a mean of the two can hide one.
 */
function coreLane(store, file, gameNo) {
    const p = { file, game: gameNo, until: 600 };
    const sql = name => fs.readFileSync(path.join(QUERIES, `${name}.sql`), 'utf8');
    const key = r => `${r.team}:${r.pos}`;
    const lh = Object.fromEntries(store.query(sql('lasthit_cores'), p).map(r => [key(r), r]));
    const cost = Object.fromEntries(store.query(sql('core_costs'), p).map(r => [key(r), r]));
    const conv = r => (r && r.near > 0 ? r.core_lh / r.near : undefined);
    const mean = (a, b) => (a === undefined || a === null || b === undefined || b === null ? undefined : (a + b) / 2);
    const out = {};
    for (const n of [1, 2, 3]) {
        const [r, d] = [lh[`2:${n}`], lh[`3:${n}`]];
        out[`conv_lpos${n}`] = mean(conv(r), conv(d));
        out[`conv_lpos${n}_r`] = conv(r);
        out[`conv_lpos${n}_d`] = conv(d);
        for (const f of ['dn', 'lvl', 'hph']) out[`${f}_at_10_lpos${n}`] = mean(cost[`2:${n}`]?.[f], cost[`3:${n}`]?.[f]);
    }
    return out;
}

/** One manifest game with its parsed game and the store holding its log (storeFor): the flat metrics and the gate's problems. */
function nfGame(g, game, store) {
    const m = dynamicMetrics(store, path.resolve(g.log), game.index, game);
    const flat = { ...flatten(m), ...coreLane(store, path.resolve(g.log), game.index) };
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
    for (const [key, bySeed] of Object.entries(table)) {
        const rows = Object.values(bySeed);
        const strata = Object.keys(bySeed).map(seed => ({ off: groups[seed].filter(g => g.arm === 'off').map(g => g.flat[key]),
            on: groups[seed].filter(g => g.arm === 'on').map(g => g.flat[key]) }));
        // Pooled OFF SD: the per-seed SDs pooled by their df (as the stratified delta's variance).
        const sdRows = rows.filter(r => Number.isFinite(r.off.sd));
        const dfOff = sdRows.reduce((a, r) => a + r.off.n - 1, 0);
        const sd = dfOff ? Math.sqrt(sdRows.reduce((a, r) => a + (r.off.n - 1) * r.off.sd ** 2, 0) / dfOff) : NaN;
        const off = stats(rows.map(r => r.off.mean)), on = stats(rows.map(r => r.on.mean));
        bySeed.all = { off: { n: rows.reduce((a, r) => a + r.off.n, 0), mean: off.mean, sd }, on: { n: rows.reduce((a, r) => a + r.on.n, 0), mean: on.mean },
            mde: mde(sd, n * rows.length), ...stratified(strata) };
    }
    return table;
}

function main(argv) {
    const file = argv[0];
    const n = Number((argv.join(' ').match(/--n (\d+)/) || [])[1] || 5);
    const store = storeFor(file);
    const games = readManifest(file).map(g => {
        const parsed = parseLog(fs.readFileSync(g.log, 'utf8'));
        return nfGame(g, parsed[parsed.length - 1], store);
    });
    store.close();
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
    console.log(`\nmetric | seed | OFF mean | OFF SD | n | MDE (N=${n} per seed) | ON mean | ON-OFF | 95% CI (Welch per seed; all = seeds as strata, pooled variance)`);
    for (const [key, bySeed] of Object.entries(table)) {
        for (const [seed, r] of Object.entries(bySeed)) {
            console.log(`${key} | ${seed} | ${f(r.off.mean)} | ${f(r.off.sd)} | ${r.off.n} | ${f(r.mde)} | ${f(r.on.mean)} | ${f(r.delta)} | ${f(r.lo)} to ${f(r.hi)}`);
        }
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { coreLane, flatten, gate, stats, mde, t975, tCrit, welch, stratified, nfGame, noiseTable, storeFor, stackInterrupted };
