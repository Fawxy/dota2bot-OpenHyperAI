'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { xpOf, noise } = require('../gate');

test('experience from level and XP still needed: the spans below the level plus the part of its own span done', () => {
    assert.strictEqual(xpOf(1, 240), 0);
    assert.strictEqual(xpOf(3, 500), 240 + 400 + 20);
    assert.throws(() => xpOf(2, 401), /level table/);
});

// Rows whose per-cell deviations are given; every cell holds a +v and a -v game, so the cell mean is 0 and the pooled
// covariance is the deviations' own.
function rows(devs) {
    return devs.flatMap(([deaths, nw, xp], i) => [1, -1].map((s) => ({
        label: `x_${String.fromCharCode(65 + (i % 3))}_${i % 2 ? 'rad' : 'dire'}_${i}`,
        cell: `c${i}`, d: { deaths: s * deaths, nw: s * nw, xp: s * xp },
    })));
}

test('null tolerances: three independent measures need a wider k than three that fail together', () => {
    const indep = noise(rows([[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 0, 0], [0, 1, 0], [0, 0, 1]]), { sims: 100000 });
    // Each of three independent one-sided tests at 0.9^(1/3): k = 1.82.
    assert.ok(Math.abs(indep.k - 1.82) < 0.04, `independent k ${indep.k}`);
    // More deaths moving with less net worth and experience: one test in effect, k = 1.28.
    const together = noise(rows([[1, -1, -1], [2, -2, -2], [1, -1, -1]]), { sims: 100000 });
    assert.ok(Math.abs(together.k - 1.28) < 0.04, `together k ${together.k}`);
    // Deaths moving with net worth up: their worse directions never coincide, so k is wider than when they fail together.
    const opposed = noise(rows([[1, 1, 0], [2, 2, 0], [0, 0, 1], [0, 0, 2]]), { sims: 100000 });
    assert.ok(opposed.k > together.k, `opposed k ${opposed.k}`);
    assert.ok(Math.abs(together.tol.deaths - together.k * together.sd.deaths * Math.sqrt(2 / 10)) < 1e-9);
});
