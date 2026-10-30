'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { t975, tCrit, welch, stratified, noiseTable, mde, stackInterrupted } = require('../nf');

const near = (a, b, eps, msg) => assert.ok(Math.abs(a - b) < eps, `${msg}: ${a} vs ${b}`);

test('t975 matches t tables', () => {
    for (const [df, t] of [[3, 3.182], [4, 2.776], [8, 2.306], [16, 2.12], [30, 2.042], [40, 2.021], [1000, 1.962]]) near(t975(df), t, 0.002, `df ${df}`);
    near(t975(4.5), 2.66, 0.01, 'df 4.5 between the table rows'); // exact 2.6589 (tCrit)
});

test('welch: equal SDs and N give df 2N-2 and the pooled-t interval', () => {
    const r = welch({ n: 5, mean: 10, sd: 2 }, { n: 5, mean: 12, sd: 2 });
    near(r.delta, 2, 1e-9, 'delta');
    near(r.df, 8, 1e-9, 'df');
    near(r.hi - r.delta, 2.306 * Math.sqrt(1.6), 0.02, 'half width');
});

test('welch: zero spread in both arms gives a point interval', () => {
    const r = welch({ n: 5, mean: 0, sd: 0 }, { n: 5, mean: 1, sd: 0 });
    assert.strictEqual(r.lo, 1);
    assert.strictEqual(r.hi, 1);
});

test('stratified: balanced seeds give the mean of the seed deltas with the pooled-t interval', () => {
    // Two seeds, 3 games per arm, every arm SD 1: s^2 = 1, df = 2 * (3 + 3 - 2) = 8, sum of weights 2 * 1.5 = 3.
    const p = stratified([{ off: [9, 10, 11], on: [11, 12, 13] }, { off: [19, 20, 21], on: [23, 24, 25] }]);
    near(p.delta, 3, 1e-9, 'delta');
    near(p.df, 8, 1e-9, 'df');
    near(p.se, Math.sqrt(1 / 3), 1e-9, 'se');
    near(p.hi - p.delta, 2.306 * p.se, 0.01, 'half width');
});

test('stratified: a seed with one game per arm counts in the delta, a one-arm seed does not (slice 4 lineup C)', () => {
    const two = [{ off: [9, 11], on: [11, 13] }, { off: [19, 21], on: [23, 25] }];
    const p = stratified([...two, { off: [30], on: [20] }, { off: [5, 6], on: [] }]);
    // Weights 1, 1, 0.5: (2 + 4 - 10 * 0.5) / 2.5. Per-seed Welch gave lineup C no SE and left it out.
    near(p.delta, 0.4, 1e-9, 'delta');
    near(p.df, 4, 1e-9, 'df from the two-game seeds only');
    assert.ok(Number.isFinite(p.lo) && p.lo < p.delta, 'a CI');
    const q = stratified([{ off: [30], on: [20] }, { off: [1], on: [2] }]);
    assert.ok(Number.isFinite(q.delta) && Number.isNaN(q.lo), 'one game per arm everywhere: a delta, no CI');
});

test('stratified: unbalanced arms weight a seed by its effective pair count, not equally', () => {
    // Seed 1 has 4 pairs, seed 2 one: an equal-weight mean would give 5, the effective-N weights (2, 0.5) give 2.
    const p = stratified([{ off: [0, 0, 0, 0], on: [1, 1, 1, 1] }, { off: [0], on: [17] }]);
    near(p.delta, (2 * 1 + 0.5 * 17) / 2.5, 1e-9, 'delta');
});

test('noiseTable: the pooled row uses every game and pools the OFF SD by df', () => {
    const g = (seed, arm, x) => ({ seed, arm, flat: { m: x } });
    const games = [g(30, 'off', 9), g(30, 'off', 11), g(30, 'on', 12), g(30, 'on', 14), g(25, 'off', 4), g(25, 'on', 1)];
    const all = noiseTable(games, 5).m.all;
    assert.strictEqual(all.off.n, 3);
    near(all.off.sd, Math.SQRT2, 1e-9, 'OFF SD from seed 30 only (seed 25 has one OFF game)');
    near(all.delta, (1 * 3 + 0.5 * -3) / 1.5, 1e-9, 'delta includes the one-game seed');
    assert.ok(Number.isFinite(all.lo), 'CI');
});

test('mde over pooled seeds equals mde at N times seeds', () => {
    near(mde(2, 15), (2.048 + 0.855) * 2 * Math.sqrt(2 / 15), 0.1, 'N=15');
});

test('stackInterrupted: OHA take-overs and the job stop on hero damage, not execution failures (slice 4 Amendment 1)', () => {
    for (const why of ['cancelled:hit', 'cancelled:run', 'cancelled:defend-ping', 'preempted:mode=3', 'preempted:never_started'])
        assert.strictEqual(stackInterrupted({ res: 'failed', why }), true, why);
    for (const why of ['ok', 'missed:mistake:no-aggro', 'no_target:mistake:no-camp', 'preempted:stalled', undefined])
        assert.strictEqual(stackInterrupted({ res: 'failed', why }), false, String(why));
});

test('tCrit is the exact two-sided t quantile at any alpha and fractional df', () => {
    // Tables: alpha 0.05 (t975), 0.025 per look (t 0.9875), 0.01 (t 0.995).
    for (const [a, df, t] of [[0.05, 4, 2.776], [0.05, 30, 2.042], [0.025, 8, 2.752], [0.025, 20, 2.423], [0.01, 10, 3.169], [0.05, 1, 12.706]]) {
        near(tCrit(a, df), t, 0.002, `alpha ${a} df ${df}`);
    }
    near(tCrit(0.05, 4.5), 2.6589, 0.001, 'df 4.5 (numeric integration of the t density)');
    assert.ok(tCrit(0.025, 12) > tCrit(0.05, 12), 'a smaller alpha gives a wider interval');
});
