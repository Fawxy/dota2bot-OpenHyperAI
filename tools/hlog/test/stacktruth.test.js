'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { grade, campMap, boxesOf, nin, tiers } = require('../stacktruth');

// Spawner origins as the replay gives them (good_1, good_2 and one far camp); a snapshot row is
// [ent, kind, spawner or player, x, y, maxd since :45, first second GUARD out or -1].
const SP = [{ ent: 527, x: 3978, y: -5027 }, { ent: 2516, x: 4649, y: -3699 }, { ent: 221, x: 1922, y: -3975 }];
// good_1 with a box 700 wide (x 3700-4400) and 400 high, as `campMap` gives it.
const G1 = { ...SP[0], box: { x0: 3700, y0: -5250, x1: 4400, y1: -4850 } };

test('a camp that spawned at :00.1 of the next minute with its earlier neutrals alive is stacked', () => {
  const t = { nc: [{ sp: 527, t: 300.1 }], snap: { 4: [[1, 'n', 527, 3980, -5020, 0, -1]] }, alive: { 4: { 527: 3 } } };
  assert.deepStrictEqual(grade(G1, 4, t), { true: 1 });
});

test('a camp cleared before :00 spawns too: a respawn, not a stack', () => {
  const t = { nc: [{ sp: 527, t: 300.1 }], snap: { 4: [] }, alive: { 4: { 2516: 3 } } };
  assert.deepStrictEqual(grade(G1, 4, t), { true: 0, block: 'respawn' });
});

test('a spawn of another camp, or of this camp a minute later, does not count', () => {
  const t = { nc: [{ sp: 2516, t: 300.1 }, { sp: 527, t: 360.1 }], snap: { 4: [] } };
  assert.strictEqual(grade(G1, 4, t).true, 0);
});

test('units in the box are split into own neutrals that never left, left too late or came back, and the rest', () => {
  // psolo5a_A_solorad (31/10/2026 replay) minute 3: good_1 did not spawn; one troll never got 400 out.
  const t = { nc: [], snap: { 3: [
    [373, 'n', 527, 4292, -5011, 294, -1],
    [1161, 'n', 527, 4388, -4964, 494, 59.7],
    [1200, 'n', 527, 4100, -5000, 900, 55.8],
    [1300, 'n', 2516, 4300, -4900, 0, -1],
    [9, 'h', 3, 4200, -5100],
    [1400, 'n', 527, 4450, -5027, 1300, 55],
  ] } };
  const g = grade(G1, 3, t);
  assert.strictEqual(g.true, 0);
  assert.strictEqual(g.block, 'stay:1,late:1,back:1@55.8,other:1,hero:1');
});

test('a neutral that came back carries where it turned and how far the nearest hero was then', () => {
  const t = { nc: [], snap: { 3: [[1200, 'n', 527, 4100, -5000, 900, 55.8, 57.2, 740]] } };
  assert.strictEqual(grade(G1, 3, t).block, 'back:1@55.8>57.2:740');
});

test('nothing near a camp that did not spawn reads none', () => {
  assert.strictEqual(grade(G1, 3, { nc: [], snap: {} }).block, 'none');
});

test('ev=camp lines give each camp number its box and the replay spawner at its origin', () => {
  const b = boxesOf('[HEV] t=0.5 ev=camp idx=1 team=2 type=small x=3978 y=-5027 x0=3700 y0=-5250 x1=4400 y1=-4850\r\n' +
    '[HEV] t=0.5 ev=camp idx=2 team=2 type=large x=4649 y=-3699 x0=4400 y0=-3900 x1=4900 y1=-3500\n');
  const m = campMap(b, SP);
  assert.strictEqual(m[1].ent, 527);
  assert.strictEqual(m[2].ent, 2516);
  assert.deepStrictEqual(m[1].box, { type: 'small', x: 3978, y: -5027, x0: 3700, y0: -5250, x1: 4400, y1: -4850 });
  assert.strictEqual(boxesOf('no camp lines'), undefined);
});

test('stacks in the camp count up while its neutrals live and start again once it is empty', () => {
  // good_1: spawns onto live neutrals at 3:00 and 4:00 (two stacks), empty at 5:59.9, then one more at 7:00.
  const sp = (min) => ({ sp: 527, t: min * 60 + 0.1 });
  const t = { nc: [sp(1), sp(3), sp(4), sp(6), sp(7)], alive: { 2: { 527: 3 }, 3: { 527: 6 }, 4: { 527: 9 }, 5: { 527: 0 }, 6: { 527: 4 } } };
  assert.deepStrictEqual([3, 4, 5, 6, 7].map((m) => nin(G1, m, t)), [1, 2, 2, 0, 1]);
});

test('tiers: a pair is graded at its fuller camp and counts both camps stacked', () => {
  const r = tiers([
    { double: 1, camp: 1, fcamp: 2, nin: 0, fnin: 0, true: 1, ftrue: 1 },
    { double: 1, camp: 1, fcamp: 2, nin: 0, fnin: 1, true: 1, ftrue: 0 },
    { double: null, camp: 9, nin: 4, true: 0 },
  ]);
  assert.deepStrictEqual(r['2>1']['0'], { n: 1, b: 1, a: 1, both: 1 });
  assert.deepStrictEqual(r['2>1']['1'], { n: 1, b: 1, a: 0, both: 0 });
  assert.deepStrictEqual(r['9']['3+'], { n: 1, b: 0, a: 0, both: 0 });
});
