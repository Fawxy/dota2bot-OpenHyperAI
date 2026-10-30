'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { bar } = require('../er');

// Slice 4: the pooled rule (sum of num over sum of den across the ON games).
test('bar pooled: met at the rate, not met below it or under minDen', () => {
    const g = (arm, att, st) => ({ arm, label: arm, health: {}, flat: { stack_attempts: att, stack_stacked: st } });
    const b = { id: 's', rule: 'pooled', num: 'stack_stacked', den: 'stack_attempts', min: 0.8, minDen: 10 };
    const games = [g('on', 3, 3), g('on', 3, 2), g('on', 3, 3), g('on', 3, 3), g('off', 0, 0)];
    assert.deepStrictEqual(bar(b, games, {}), { value: '11/12 = 91.7%', result: 'met' });
    assert.strictEqual(bar(b, [g('on', 5, 3), g('on', 5, 4)], {}).result, 'not met');
    assert.strictEqual(bar(b, [g('on', 3, 3), g('on', 3, 3)], {}).result, 'not met', 'under minDen');
});
