'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { frontsAt, format } = require('../front');

const LOG = [
    '[VScript] [HEV] t=-90.000 ev=bot pid=0 hero=luna team=2 schema=2 build=abc pos=1',
    '[VScript] [HEV] t=60.000 ev=front team=2 top=0.250 topx=-3500 topy=5000 mid=0.400 midx=-1400 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=60.000 ev=front team=3 top=0.500 topx=0 topy=5000 mid=0.700 midx=2800 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=60.000 ev=snap pid=0 x=0 y=4900 alive=1 hp=100 ln=top s=0.500 ld=100',
    '[VScript] [HEV] t=61.000 ev=front team=2 top=0.300 topx=-2800 topy=5000 mid=0.400 midx=-1400 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=120.000 ev=snap pid=0 x=10 y=4900 alive=1 hp=100 ln=top s=0.510 ld=100',
].join('\n');

test('front: latest ev=front per team and ev=snap per hero at or before each clock', () => {
    const [a, b] = frontsAt(LOG, [60, 90]);
    assert.strictEqual(a.fronts[2].top, 0.25);
    assert.strictEqual(a.fronts[3].mid, 0.7);
    assert.deepStrictEqual(a.heroes.map(h => [h.hero, h.ln, h.s]), [['luna', 'top', 0.5]]);
    assert.strictEqual(b.fronts[2].top, 0.3, 'the later line wins');
    assert.strictEqual(b.heroes[0].t, 60, 'snaps after the clock are ignored');
    assert.match(format([b]), /== 1:30\nfront team 2 \(t=61\): top 0.3 \(-2800,5000\)/);
    assert.deepStrictEqual(frontsAt(LOG, [30])[0].fronts, {});
});

test('front: a log with two games reads one game at a time', () => {
    const two = LOG + '\n' + LOG.replace(/top=0\.250/, 'top=0.111');
    assert.strictEqual(frontsAt(two, [60], 1)[0].fronts[2].top, 0.25);
    assert.strictEqual(frontsAt(two, [60], 2)[0].fronts[2].top, 0.111);
    assert.deepStrictEqual(frontsAt(two, [60], 3)[0].heroes, []);
});
