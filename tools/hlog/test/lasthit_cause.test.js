'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { POLY, laneLabel } = require('../dynamic');
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
    return out.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n');
}

/** Log text plus extra lines, back in time order (a clock that goes back starts a new game). */
const inOrder = (text, ...extra) =>
    [...text.split('\n'), ...extra].sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n');

/** The log text in an in-memory store, then lasthitCause on it. */
function run(text, until = 600) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lhc-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = L.lasthitCause(s, f, 1, until);
    s.db.close();
    return out;
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
    const r = run(g).cores.r1;
    assert.strictEqual(r.lane, 'bot');
    assert.strictEqual(r.near, 5);
    assert.deepStrictEqual(r.killers, { core_lh: 1, ally_lh: 1, enemy_deny: 1, creep_or_tower: 2 });
    assert.deepStrictEqual(r.states, { late: 1, early: 1, idle_in_range: 1, away: 1 });
    assert.strictEqual(r.conversion, 1 / 5);
    assert.strictEqual(r.laneDeaths, 7);
    assert.strictEqual(r.absent, 2);
    assert.strictEqual(run(g).cores.r5, undefined, 'supports are not cores');
});

test('gates: G1 drops a core, G2/G5 drop a game, and the until cut', () => {
    const g = log([[301, 'by=1 p1d=100 p1t=1'], [302, 'by=none p1d=100'], [700, 'by=1 p1d=100']], 2);
    const res = run(g);
    assert.strictEqual(res.gates.G1.r1, 1 / 2);
    assert.strictEqual(res.gates.G2, 0);
    assert.strictEqual(res.cores.r1.near, 2, 'a death after until is left out');
    assert.strictEqual(res.keep, true);
    assert.strictEqual(res.cores.r1.keep, false, 'G1 below 0.9 drops the core');
    assert.strictEqual(L.summarise([res]).pos1, undefined);

    const ok = run(log([[301, 'by=1 p1d=100 p1t=1'], [302, 'by=none p1d=100']], 1));
    assert.strictEqual(ok.cores.r1.keep, true);
    assert.strictEqual(L.summarise([ok]).pos1.conversion[0], 1 / 2);
    assert.strictEqual(L.summarise([{ ...ok, keep: false }]).pos1, undefined, 'a dropped game is left out');
});

test('G2 counts revived creeps; G5 needs own last hits on the attacked creep and no negative attack age', () => {
    const fog = log([[301, 'by=1 p1d=100 p1t=1'], [302, 'by=none p1d=100']], 1);
    assert.deepStrictEqual(run(inOrder(fog, line(303, 'creep_revive team=2 kind=melee hp=0.3'))).failed, ['G2']);
    const neg = run(log([[301, 'by=1 p1d=100 p1t=1'], [302, 'by=5 p1d=100 p1t=1 p1a=-140']], 1));
    assert.deepStrictEqual(neg.failed, ['G5']);
    assert.strictEqual(neg.cores.r1.states.late, 1, 'a negative age is not read as a timing');
    const blind = run(log([[301, 'by=1 p1d=100 p1t=0']], 1));
    assert.deepStrictEqual(blind.failed, ['G5'], 'own last hit on a creep it was not attacking');
});

test('lane_segments is the lane polylines of dynamic.js, and its lane for a point is laneLabel', () => {
    const s = new Store(':memory:');
    s.refreshViews();
    const segs = s.query('SELECT lane, x1, y1, x2, y2 FROM lane_segments ORDER BY seg').map(r => ({ ...r }));
    const want = [];
    for (const [lane, P] of Object.entries(POLY)) for (let i = 0; i + 1 < P.length; i++) want.push({ lane, x1: P[i][0], y1: P[i][1], x2: P[i + 1][0], y2: P[i + 1][1] });
    assert.deepStrictEqual(segs, want);
    s.db.close();
});

test('a core in the mid lane and one in the top lane get their own lane (the nearest polyline, not a rounded fraction)', () => {
    // (5441, -4063) is 1500+ units from the ancient and beside the bot lane's far segment: integer division in the segment
    // projection once sent it to no lane.
    assert.strictEqual(laneLabel([5441, -4063]), 'bot');
    const text = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        ...[60, 70, 80].map(t => line(t, 'snap pid=1 x=5441 y=-4063 alive=1 lh=0')),
        line(90, 'creep_death team=2 kind=melee x=5441 y=-4000 hp=0.1 by=none p1d=500'),
    ].join('\n');
    const r = run(text).cores.r1;
    assert.strictEqual(r.lane, 'bot');
    assert.strictEqual(r.laneDeaths, 1);
});

test('logs with no game are skipped', () => {
    const fs = require('fs'), os = require('os'), path = require('path');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lhc-'));
    const think = path.join(dir, 'think.log');
    fs.writeFileSync(think, '[THINK] 1 60.0 210.0 1.0\n');
    assert.deepStrictEqual(L.gamesFrom([think]), []);
});
