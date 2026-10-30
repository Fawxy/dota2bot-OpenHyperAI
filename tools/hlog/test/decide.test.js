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
