'use strict';
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { detectStacks, detectPulls, aggregate, downsamplePath, median } = require('../detect');
const gen = require('../gen_camps');
const { summarise } = require('../parse_condebug');

const fixture = (name) => path.join(__dirname, 'fixtures', name);
const load = (name) => fs.readFileSync(fixture(name), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const campsOf = (events) => events.filter((e) => e.k === 'camp');

const tests = [];
const test = (name, fn) => tests.push([name, fn]);

test('stack detected only when count rises', () => {
    const events = load('stack_events.ndjson');
    const stacks = detectStacks(events, campsOf(events));
    assert.strictEqual(stacks.length, 1);
    assert.strictEqual(stacks[0].camp.x, 1000);
    assert.strictEqual(stacks[0].aggroSec, 54);
    assert.strictEqual(stacks[0].team, 2);
    assert.ok(stacks[0].path.length >= 2 && stacks[0].path.length <= 6);
});

test('stack outside :50-:58 ignored', () => {
    const events = load('stack_events.ndjson').map((e) => (e.k === 'dmg' && e.t === 54 ? { ...e, t: 47 } : e));
    assert.strictEqual(events.filter((e) => e.t === 47).length, 2);
    assert.strictEqual(detectStacks(events, campsOf(events)).length, 0);
});

test('pull requires lane-creep damage within 15 s', () => {
    const events = load('pull_events.ndjson');
    const pulls = detectPulls(events, campsOf(events));
    assert.strictEqual(pulls.length, 1);
    assert.strictEqual(pulls[0].aggroSec, 15);
    assert.ok(pulls[0].meet.x > 2000);

    const late = events.map((e) => (e.k === 'dmg' && e.src.startsWith('lanecreep') ? { ...e, t: 33 } : e));
    assert.strictEqual(detectPulls(late, campsOf(late)).length, 0);
});

test('pull on wrong team creeps ignored', () => {
    const events = load('pull_events.ndjson').map((e) => (e.src === 'lanecreep:2' ? { ...e, src: 'lanecreep:3' } : e));
    assert.strictEqual(detectPulls(events, campsOf(events)).length, 0);
});

test('half pull classification', () => {
    const events = load('pull_events.ndjson');
    const full = detectPulls(events, campsOf(events))[0];
    assert.strictEqual(full.half, false);
    assert.strictEqual(full.divert, 1);

    const two = events.filter((e) => !(e.k === 'dmg' && e.srcEnt > 102));
    const half = detectPulls(two, campsOf(two))[0];
    assert.strictEqual(half.divert, 0.4);
    assert.strictEqual(half.half, true);
});

test('aggregate medians', () => {
    const camp = { x: 1020, y: 990, type: 'large' };
    const meet = { x: 2000, y: 2000 };
    const pull = (aggroSec, half = false) => ({ camp, team: 2, aggroSec, meet, path: [{ x: 1, y: 1 }, meet], divert: half ? 0.4 : 1, half });
    const stack = (aggroSec) => ({ camp, team: 2, minute: 3, aggroSec, path: [{ x: 5, y: 5 }] });
    const [agg] = aggregate([53, 54, 55].map(stack), [15, 16, 14, 45, 46].map((s) => pull(s)).concat([17, 18].map((s) => pull(s, true))));
    assert.strictEqual(agg.aggroSec, 15);
    assert.strictEqual(agg.halfAggroSec, 17.5);
    assert.strictEqual(agg.stackAggroSec, 54);
    assert.deepStrictEqual(agg.samples, { stacks: 3, pulls: 5, half: 2 });

    const line = gen.buildEntry(agg);
    assert.match(line, /pullAggroSec: \[15, 45\]/);
    assert.match(line, /halfAggroSec: \[17\.5, 47\.5\]/);
    assert.match(line, /stackAggroSec: 54[,\s]/);
});

test('downsample keeps endpoints and spacing', () => {
    const pts = Array.from({ length: 40 }, (_, i) => ({ x: i * 100, y: 0 }));
    const out = downsamplePath(pts, 6);
    assert.ok(out.length <= 6 && out.length >= 2);
    assert.deepStrictEqual(out[0], pts[0]);
    assert.deepStrictEqual(out[out.length - 1], pts[39]);
    for (let i = 1; i < out.length; i++) assert.ok(Math.hypot(out[i].x - out[i - 1].x, out[i].y - out[i - 1].y) >= 150);
    assert.strictEqual(median([3, 1, 2]), 2);
    assert.strictEqual(median([1, 2, 3, 4]), 2.5);
});

test('gen_camps preserves seeds', () => {
    const src = path.join(__dirname, '../../../typescript/bots/FunLib/humaniser/camps_data.ts');
    const original = fs.readFileSync(src, 'utf8');
    assert.ok(original.includes('// BEGIN GENERATED REPLAY ENTRIES') && original.includes('// END GENERATED REPLAY ENTRIES'));
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mining-'));
    try {
        const data = path.join(dir, 'camps_data.ts');
        const aggPath = path.join(dir, 'aggregate.json');
        fs.writeFileSync(data, original);
        const camp = { x: -3100, y: -4200, type: 'large' };
        const agg = aggregate(
            [{ camp, team: 2, minute: 2, aggroSec: 54, path: [{ x: 0, y: 0 }] }],
            [{ camp, team: 2, aggroSec: 18, meet: { x: -2000, y: -6000 }, path: [{ x: -3000, y: -4300 }, { x: -2000, y: -6000 }], divert: 1, half: false }]
        );
        fs.writeFileSync(aggPath, JSON.stringify(agg));
        const summary = gen.run(aggPath, data);
        assert.strictEqual(summary.covered, 1);

        const after = fs.readFileSync(data, 'utf8');
        const marks = (t) => [t.indexOf('// BEGIN GENERATED REPLAY ENTRIES'), t.indexOf('// END GENERATED REPLAY ENTRIES')];
        const [ob, oe] = marks(original);
        const [nb, ne] = marks(after);
        assert.strictEqual(after.slice(0, nb), original.slice(0, ob));
        assert.strictEqual(after.slice(ne), original.slice(oe));
        const block = after.slice(nb, ne);
        assert.ok(block.includes('source: "replay"'));
        assert.ok(block.includes('laneKind: "safe"'));
        assert.ok(block.includes('pullAggroSec: [18, 48]'));

        gen.run(aggPath, data);
        assert.strictEqual(fs.readFileSync(data, 'utf8'), after);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test('condebug summary', () => {
    const rows = summarise(fs.readFileSync(fixture('console.log'), 'utf8').split('\n'));
    const find = (camp, kind) => rows.find((r) => r.camp === camp && r.kind === kind);

    const half = find(12, 'half');
    assert.strictEqual(half.attempts, 7);
    assert.strictEqual(half.ok, 6);
    assert.ok(half.suggestion.includes('halfAggroSec: [17.9, 47.9]') && half.suggestion.includes('radiant_safe_large'));
    assert.ok(Math.abs(half.medianAggroError - 1.0) < 1e-9);

    const few = find(7, 'full');
    assert.strictEqual(few.attempts, 3);
    assert.strictEqual(few.suggestion, undefined);

    const stack = find(4, 'stack');
    assert.strictEqual(stack.attempts, 5);
    assert.ok(stack.suggestion.includes('stackAggroSec: 53.8'));
});

let failed = 0;
for (const [name, fn] of tests) {
    try {
        fn();
        console.log(`ok   ${name}`);
    } catch (e) {
        failed++;
        console.log(`FAIL ${name}\n${e.stack}`);
    }
}
console.log(`${tests.length - failed}/${tests.length} mining tests passed`);
process.exit(failed ? 1 : 0);
