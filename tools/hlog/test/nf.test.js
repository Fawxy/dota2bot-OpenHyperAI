'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { t975, tCrit, welch, pooled, mde } = require('../nf');

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

test('pooled: equal-weight mean of seed deltas, Satterthwaite df', () => {
    const a = welch({ n: 5, mean: 10, sd: 2 }, { n: 5, mean: 12, sd: 2 });
    const b = welch({ n: 5, mean: 20, sd: 2 }, { n: 5, mean: 24, sd: 2 });
    const p = pooled([a, b]);
    near(p.delta, 3, 1e-9, 'delta');
    near(p.se, Math.sqrt(3.2) / 2, 1e-9, 'se');
    near(p.df, 16, 1e-9, 'df');
    near(p.hi - p.delta, 2.12 * p.se, 0.01, 'half width');
});

test('mde over pooled seeds equals mde at N times seeds', () => {
    near(mde(2, 15), (2.048 + 0.855) * 2 * Math.sqrt(2 / 15), 0.1, 'N=15');
});

test('tCrit is the exact two-sided t quantile at any alpha and fractional df', () => {
    // Tables: alpha 0.05 (t975), 0.025 per look (t 0.9875), 0.01 (t 0.995).
    for (const [a, df, t] of [[0.05, 4, 2.776], [0.05, 30, 2.042], [0.025, 8, 2.752], [0.025, 20, 2.423], [0.01, 10, 3.169], [0.05, 1, 12.706]]) {
        near(tCrit(a, df), t, 0.002, `alpha ${a} df ${df}`);
    }
    near(tCrit(0.05, 4.5), 2.6589, 0.001, 'df 4.5 (numeric integration of the t density)');
    assert.ok(tCrit(0.025, 12) > tCrit(0.05, 12), 'a smaller alpha gives a wider interval');
});
