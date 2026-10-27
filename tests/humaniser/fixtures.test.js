'use strict';
// The fixture runner's own logic: expectation terms, schema checks, skill samples, Lua literals.
const test = require('node:test');
const assert = require('node:assert');
const { validate, skills, toLua, holds, judge } = require('./fixtures');

const obs = { actions: [{ verb: 'lastHit', target: 'creep#1' }, { verb: 'hold' }], desire: { retreat: 0.85 }, fact: { base: 0.85 } };

test('action terms match the verb, and the target when given', () => {
    assert.strictEqual(holds('lastHit(creep#1)', obs, 1e-6), true);
    assert.strictEqual(holds('lastHit(creep#2)', obs, 1e-6), false);
    assert.strictEqual(holds('lastHit', obs, 1e-6), true);
    assert.strictEqual(holds('deny', obs, 1e-6), false);
    assert.strictEqual(holds('hold', obs, 1e-6), true);
});

test('comparisons read desire and fact values and use the tolerance', () => {
    assert.strictEqual(holds('desire.retreat <= fact.base', obs, 1e-6), true);
    assert.strictEqual(holds('desire.retreat < fact.base', obs, 1e-6), false);
    assert.strictEqual(holds('desire.retreat == 0.8500001', obs, 1e-6), true);
    assert.strictEqual(holds('desire.retreat > 0.9', obs, 1e-6), false);
    assert.throws(() => holds('desire.laning > 0', obs, 1e-6), /not observed/);
});

test('judge: a failed must and a held mustNot are both reported; an unobserved value fails the term', () => {
    const fx = { expect: { must: ['deny(creep#2)', 'fact.missing > 0'], mustNot: ['hold'] } };
    const p = judge(fx, obs);
    assert.strictEqual(p.length, 3);
    assert.match(p[1], /not observed/);
    assert.deepStrictEqual(judge({ expect: { must: ['hold'], mustNot: ['deny'] } }, obs), []);
});

test('validate: required fields, source, status, retired reason, control shape', () => {
    const ok = { id: 'a', source: 'log', ref: {}, status: 'active', decision: 'laning_mode', world: {}, expect: { must: ['hold'] } };
    assert.deepStrictEqual(validate(ok), []);
    assert.ok(validate({ ...ok, source: 'hunch' }).some(p => /source/.test(p)));
    assert.ok(validate({ ...ok, status: 'retired' }).some(p => /reason/.test(p)));
    assert.ok(validate({ ...ok, decision: 'nope' }).some(p => /driver/.test(p)));
    assert.ok(validate({ ...ok, expect: {} }).some(p => /neither/.test(p)));
    assert.ok(validate({ ...ok, control: { commit: 'zz', outcome: 'fail' } }).some(p => /control/.test(p)));
    const { world, ...noWorld } = ok;
    assert.ok(validate(noWorld).some(p => /missing world/.test(p)));
});

test('skills: a range gives lo, midpoint and hi; a number itself; none one default run', () => {
    assert.deepStrictEqual(skills({ conditions: { skill: [0.2, 1] } }), [0.2, 0.6, 1]);
    assert.deepStrictEqual(skills({ conditions: { skill: 0.8 } }), [0.8]);
    assert.deepStrictEqual(skills({}), [null]);
});

test('toLua: tables keep string keys, arrays stay arrays', () => {
    assert.strictEqual(toLua({ a: [1, 'x'], b: null, c: true }), '{["a"] = {1, "x"}, ["b"] = nil, ["c"] = true}');
});

test('validate: action verbs must be the driver\'s, and a skill range two ordered numbers in 0-1', () => {
    const ok = { id: 'a', source: 'log', ref: {}, status: 'active', decision: 'laning_mode', world: {}, expect: { mustNot: ['deny(creep#2)'] } };
    assert.deepStrictEqual(validate(ok), []);
    assert.ok(validate({ ...ok, expect: { mustNot: ['deyn(creep#2)'] } }).some(p => /verb deyn/.test(p)));
    assert.deepStrictEqual(validate({ ...ok, expect: { must: ['desire.laning >= 0.9'] } }), []);
    assert.ok(validate({ ...ok, conditions: { skill: [1, 0.2] } }).some(p => /skill/.test(p)));
    assert.ok(validate({ ...ok, conditions: { skill: [0.2] } }).some(p => /skill/.test(p)));
});

test('toLua: quotes, backslashes, control and non-ASCII characters become Lua decimal escapes; non-finite numbers nil', () => {
    assert.strictEqual(toLua('a"b\\c\n'), String.raw`"a\34b\92c\10"`);
    assert.strictEqual(toLua('é'), String.raw`"\195\169"`);
    assert.strictEqual(toLua(Infinity), 'nil');
    assert.strictEqual(toLua(NaN), 'nil');
});
