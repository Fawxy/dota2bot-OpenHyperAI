'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { decide } = require('../decide');

const each = { id: 'H1 lua_ours', rule: 'each', metric: 'lua_ours', max: 0 };
const delta = { id: 'B1', rule: 'delta', metric: 'm', alpha: 0.025, met: { lo: { gt: 0 } } };
const stacked = { id: 'S2a', rule: 'pooled', num: 'stack_stacked', den: 'stack_clean', min: 0.8, minDen: 10, cap: 4 };
const r = (b, result, extra = {}) => ({ b, result, ...extra });

test('decide: a failed each bar stops at once, mid-batch', () => {
    const d = decide([r(each, 'not met'), r(delta, 'met')], { on: 2, off: 2, look: 9, max: 15 });
    assert.strictEqual(d.stop, true);
    assert.match(d.reason, /H1 lua_ours/);
});

test('decide: a delta bar met before the look does not stop (decided only at the look or the maximum N)', () => {
    const d = decide([r(each, 'met'), r(delta, 'met')], { on: 5, off: 5, look: 9, max: 15 });
    assert.strictEqual(d.stop, false);
});

test('decide: at the look every bar met stops; one delta bar not met goes on', () => {
    assert.strictEqual(decide([r(each, 'met'), r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 }).stop, true);
    const d = decide([r(each, 'met'), r(delta, 'not met')], { on: 9, off: 9, look: 9, max: 15 });
    assert.strictEqual(d.stop, false);
    assert.match(d.reason, /interim look: not met B1/);
});

test('decide: the look is not taken mid-pair (ON at the look, OFF one short)', () => {
    assert.strictEqual(decide([r(delta, 'met')], { on: 9, off: 8, look: 9, max: 15 }).stop, false);
});

test('decide: a capped pooled rate stops once the remaining games cannot reach the bar, and once they cannot spoil it', () => {
    // 3 ON games left at 4 attempts each: 2/10 can rise to at most 14/22 = 0.64 < 0.8.
    assert.strictEqual(decide([r(stacked, 'not met', { num: 2, den: 10 })], { on: 2, off: 2, look: 0, max: 5 }).stop, true);
    // 3/10 with 12 more possible: 15/22 = 0.68, still short: decided not met.
    assert.strictEqual(decide([r(stacked, 'not met', { num: 3, den: 10 })], { on: 2, off: 2, look: 0, max: 5 }).stop, true);
    // 9/10 with 12 more possible: 21/22 could still reach, 9/22 could still fall short: open.
    assert.strictEqual(decide([r(stacked, 'met', { num: 9, den: 10 })], { on: 2, off: 2, look: 0, max: 5 }).stop, false);
    // 40/40 with 4 more possible: at worst 40/44 = 0.91: decided met, and with no other bar the batch stops.
    const d = decide([r(stacked, 'met', { num: 40, den: 40 })], { on: 4, off: 4, look: 0, max: 5 });
    assert.deepStrictEqual([d.stop, d.reason], [true, 'every bar decided']);
});

test('decide: a pooled bar without cap stays open until the maximum N', () => {
    const b = { ...stacked, cap: undefined };
    assert.strictEqual(decide([r(b, 'not met', { num: 0, den: 10 })], { on: 4, off: 4, look: 0, max: 5 }).stop, false);
});

test('decide: an each bar with no valid game of its arm yet does not stop the batch, and is not met at the maximum', () => {
    const { bar } = require('../er');
    const none = bar(each, [{ arm: 'off', label: 'off1', flat: { lua_ours: 0 } }], {});
    const mid = decide([{ b: each, ...none }, r(delta, 'met')], { on: 1, off: 1, look: 9, max: 15 });
    assert.strictEqual(mid.stop, false);
    assert.strictEqual(mid.states[0], 'open');
    const end = decide([{ b: each, ...none }, r(delta, 'met')], { on: 15, off: 15, look: 9, max: 15 });
    assert.strictEqual(end.states[0], 'not met');
});

// Review 2026-10-30 eval-cost cc9740e H1, L1, L2: the interim look does not decide a pooled bar or an each bar with no game.
test('decide: at the look a pooled bar the remaining games can still meet keeps the batch going', () => {
    const uncapped = { ...stacked, cap: undefined };
    // 6/7, under minDen 10, at look 9 of 15: open, not failed.
    const a = decide([r(uncapped, 'not met', { num: 6, den: 7, maxDen: 1 }), r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 });
    assert.deepStrictEqual([a.stop, a.states[0]], [false, 'open']);
    // 15/20 with 6 ON games of at most 4 left: 39/44 = 0.89 can still be reached, 15/44 can still fall short.
    const b = decide([r(stacked, 'not met', { num: 15, den: 20, maxDen: 4 }), r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 });
    assert.deepStrictEqual([b.stop, b.states[0]], [false, 'open']);
    assert.match(b.reason, /interim look: open S2a; going on/);
    // A met but undecided pooled bar does not end the batch at the look either.
    assert.strictEqual(decide([r(stacked, 'met', { num: 18, den: 20, maxDen: 4 }), r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 }).stop, false);
    // A capped bar the remaining games cannot rescue still stops at the look: 2/20 + 24 = 26/44 = 0.59.
    assert.strictEqual(decide([r(stacked, 'not met', { num: 2, den: 20, maxDen: 4 }), r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 }).stop, true);
});

test('decide: an each bar with no valid game at the look stays open', () => {
    const { bar } = require('../er');
    const none = bar(each, [{ arm: 'off', label: 'off1', flat: { lua_ours: 0 } }], {});
    const d = decide([{ b: each, ...none }, r(delta, 'met')], { on: 9, off: 9, look: 9, max: 15 });
    assert.deepStrictEqual([d.stop, d.states[0]], [false, 'open']);
    assert.match(d.reason, /open H1 lua_ours \(no valid game\)/);
});

test('decide: a look at the maximum N is the maximum N (every bar decided, no "going on")', () => {
    const d = decide([r(each, 'met', { n: 5 }), r(delta, 'not met')], { on: 5, off: 5, look: 5, max: 5 });
    assert.deepStrictEqual([d.stop, d.reason], [true, 'every bar decided']);
});

// H2: the remaining games are those of the bar's own arms.
test('decide: a capped pooled bar over both arms counts the remaining games of both', () => {
    const both = { ...stacked, arms: ['on', 'off'] };
    // 6/10 at 3/3 of 5: 4 games of 4 left = 22/26 = 0.85 reachable, so open (ON alone would give 14/18 = 0.78 and a stop).
    const d = decide([r(both, 'not met', { num: 6, den: 10, maxDen: 4 })], { on: 3, off: 3, look: 0, max: 5 });
    assert.deepStrictEqual([d.stop, d.states[0]], [false, 'open']);
    // OFF only, mid-pair (ON 3, OFF 2): 3 OFF games left, 6/10 + 12 = 18/22 = 0.82, open; with 2 left it would stop.
    const off = { ...stacked, arms: ['off'] };
    assert.strictEqual(decide([r(off, 'not met', { num: 6, den: 10, maxDen: 4 })], { on: 3, off: 2, look: 0, max: 5 }).states[0], 'open');
});

// M1: a game above the cap means the cap is wrong; the bar is then judged only at the maximum N, and the reason says so.
test('decide: a capped pooled bar a game has exceeded is left open until the maximum N', () => {
    const d = decide([r(stacked, 'not met', { num: 2, den: 10, maxDen: 6 })], { on: 2, off: 2, look: 0, max: 5 });
    assert.deepStrictEqual([d.stop, d.states[0]], [false, 'open']);
    assert.match(d.reason, /over cap, open until the maximum N: S2a \(a game added 6 > cap 4\)/);
    assert.strictEqual(decide([r(stacked, 'not met', { num: 2, den: 10, maxDen: 6 })], { on: 5, off: 5, look: 0, max: 5 }).states[0], 'not met');
});
