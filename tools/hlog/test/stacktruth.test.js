'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { grade, campMap } = require('../stacktruth');

// Spawner origins as the replay gives them (good_1, good_2 and one far camp); a snapshot row is
// [ent, kind, spawner or player, x, y, maxd since :45, first second GUARD out or -1].
const SP = [{ ent: 527, x: 3978, y: -5027 }, { ent: 2516, x: 4649, y: -3699 }, { ent: 221, x: 1922, y: -3975 }];

test('a camp that spawned at :00.1 of the next minute is stacked, whatever stood near it', () => {
  const t = { nc: [{ sp: 527, t: 300.1 }], snap: { 4: [[1, 'n', 527, 3980, -5020, 0, -1]] } };
  assert.deepStrictEqual(grade(SP[0], 4, t), { true: 1 });
});

test('a spawn of another camp, or of this camp a minute later, does not count', () => {
  const t = { nc: [{ sp: 2516, t: 300.1 }, { sp: 527, t: 360.1 }], snap: { 4: [] } };
  assert.strictEqual(grade(SP[0], 4, t).true, 0);
});

test('own neutrals near the origin are split into never left, out too late and came back', () => {
  // psolo5a_A_solorad (31/10/2026 replay) minute 3: good_1 did not spawn; one troll never got 400 out.
  const t = { nc: [], snap: { 3: [
    [373, 'n', 527, 4292, -5011, 294, -1],
    [1161, 'n', 527, 4488, -4964, 494, 59.7],
    [1200, 'n', 527, 4100, -5000, 900, 55.8],
    [1300, 'n', 2516, 4300, -4800, 0, -1],
    [9, 'h', 3, 4200, -5100],
    [1400, 'n', 527, 5200, -5027, 1300, 55],
  ] } };
  const g = grade(SP[0], 3, t);
  assert.strictEqual(g.true, 0);
  assert.strictEqual(g.block, 'stay:1,late:1,back:1@55.8,other:1,hero:1');
});

test('a neutral that came back carries where it turned and how far the nearest hero was then', () => {
  const t = { nc: [], snap: { 3: [[1200, 'n', 527, 4100, -5000, 900, 55.8, 57.2, 740]] } };
  assert.strictEqual(grade(SP[0], 3, t).block, 'back:1@55.8>57.2:740');
});

test('nothing near a camp that did not spawn reads none', () => {
  assert.strictEqual(grade(SP[0], 3, { nc: [], snap: {} }).block, 'none');
});

test('camp numbers map by the line cx/cy; a camp A with no line of its own is its B nearest other spawner', () => {
  const m = campMap([{ camp: 1, cx: 3978, cy: -5027, fcamp: 2 }], SP);
  assert.strictEqual(m[1].ent, 527);
  assert.strictEqual(m[2].ent, 2516);
});
