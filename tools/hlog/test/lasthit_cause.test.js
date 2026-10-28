'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { parseLog } = require('../parse');
const L = require('../lasthit_cause');

// Radiant safe lane (bot) near its T1, as in dynamic.test.js.
const BOT = [-360, -6256];
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

/** A Radiant pos-1 core (pid 1) and pos-5 support (pid 5) in the bot lane, a Dire mid (pid 7); deaths as given. */
function log(deaths, lh = 1) {
    const out = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=7 hero=h7 team=3 pos=2'),
    ];
    for (let t = 1; t <= 600; t += 10) {
        out.push(line(t, `snap pid=1 x=${BOT[0]} y=${BOT[1]} alive=1 lh=${t > 300 ? lh : 0}`));
        out.push(line(t, `snap pid=5 x=${BOT[0]} y=${BOT[1]} alive=1 lh=0`));
        out.push(line(t, 'snap pid=7 x=0 y=0 alive=1 lh=0'));
    }
    for (const [t, f] of deaths) out.push(line(t, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 ${f}`));
    return parseLog(out.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n'))[0];
}

test('deaths near a core are split by killer and, when lost, by what the core was doing', () => {
    const g = log([
        [301, 'by=1 p1d=100 p1r=150 p1t=1 p1a=0.3'],
        [310, 'by=5 p1d=100 p1r=150 p1t=1 p1a=0.2'], // lost late: its swing had just started
        [320, 'by=none p1d=100 p1r=150 p1t=1 p1a=0.9'], // lost early: it hit and the creep lived
        [330, 'by=deny p1d=300 p1r=150 p1t=0'], // idle in range (150 + 300)
        [340, 'by=none p1d=900 p1r=150 p1t=0'], // within R, away
        [350, 'by=none p1d=1400 p1r=150 p1t=0'], // beyond R: absent
        [360, 'by=none'], // in the core's lane, no core near: absent
    ]);
    const r = L.lasthitCause(g).cores.r1;
    assert.strictEqual(r.lane, 'bot');
    assert.strictEqual(r.near, 5);
    assert.deepStrictEqual(r.killers, { core_lh: 1, ally_lh: 1, enemy_deny: 1, creep_or_tower: 2 });
    assert.deepStrictEqual(r.states, { late: 1, early: 1, idle_in_range: 1, away: 1 });
    assert.strictEqual(r.conversion, 1 / 5);
    assert.strictEqual(r.laneDeaths, 7);
    assert.strictEqual(r.absent, 2);
    assert.strictEqual(L.lasthitCause(g).cores.r5, undefined, 'supports are not cores');
});

test('gates: G1 attributed share of the core counter, G2 fog-death share, and the until cut', () => {
    const g = log([[301, 'by=1 p1d=100'], [302, 'by=none p1d=100'], [700, 'by=1 p1d=100']], 2);
    const res = L.lasthitCause(g);
    assert.strictEqual(res.gates.G1.r1, 1 / 2);
    assert.strictEqual(res.gates.G2, 0);
    assert.strictEqual(res.cores.r1.near, 2, 'a death after until is left out');
    const s = L.summarise([res]);
    assert.strictEqual(s.pos1.n, 1);
    assert.strictEqual(s.pos1.conversion[0], 1 / 2);
});
