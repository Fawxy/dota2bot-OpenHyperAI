'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { stealsFor } = require('../steals');
const D = require('../dynamic');

const BOT = [-360, -6256];
const line = (t, f) => `[HEV] t=${Number(t).toFixed(3)} ev=${f}`;
const byTime = lines => lines.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));

/** Radiant pids 1-5 hold positions 1-5 and all have snaps; pid 5 is in mode `laning` from t=50. Deaths are [t, fields]. */
function log(deaths, { drop, extra = [] } = {}) {
    const out = [];
    for (let p = 1; p <= 5; p++) if (p !== drop) out.push(line(0, `bot pid=${p} hero=h${p} team=2 pos=${p}`));
    for (let t = 1; t <= 700; t += 10) {
        for (let p = 1; p <= 5; p++) if (p !== drop) out.push(line(t, `snap pid=${p} x=${BOT[0]} y=${BOT[1]} alive=1 mode=${p === 5 && t >= 50 ? 'laning' : 'idle'}`));
    }
    for (const [t, f] of deaths) out.push(line(t, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1]} hp=0.1 ${f}`));
    return byTime([...out, ...extra]).join('\n');
}

/** The cases for log text, in an in-memory store (several games: the text is one log, `game` picks). */
function run(text, until = 600, game = 1) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-steals-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = stealsFor(s, f, game, until);
    s.db.close();
    return out;
}

test('steals: a support last hit counts when a logged core was attacking the creep or within range + 150', () => {
    const cases = run(log([
        [100.2, 'by=5 p1d=300 p1r=150'], // in range + 150: counted, with the support's mode
        [110, 'by=5 p1d=900 p1r=150 p1t=1'], // attacking: counted
        [120, 'by=5 p1d=301 p1r=150'], // just beyond: not
        [130, 'by=5'], // no core logged: not
        [140, 'by=1 p1d=50 p1r=150'], // the core's own last hit: not
        [150, 'by=3 p1d=50 p1r=150'], // pos3 core's: not
        [160, 'by=deny p1d=50 p1r=150'], // an enemy deny: not
        [170, 'by=4 p2d=100 p2r=150 p3d=900 p3r=150 p3t=0'], // pos4, the second core only
    ]));
    assert.deepStrictEqual(cases.map(c => c.t), [100.2, 110, 170]);
    assert.deepStrictEqual(cases.map(c => [c.pid, c.pos, c.team, c.kind]), [[5, 5, 2, 'melee'], [5, 5, 2, 'melee'], [4, 4, 2, 'melee']]);
    assert.strictEqual(cases[0].mode, 'laning');
    assert.deepStrictEqual(cases[1].cores, [{ core: 1, d: 900, r: 150, attacking: true }]);
    assert.deepStrictEqual(cases[2].cores, [{ core: 2, d: 100, r: 150, attacking: false }], 'only the cores that could take it are listed');
    assert.strictEqual(cases[2].mode, 'idle');
});

test('steals: the swing-start mode bm wins over the snapshot mode; swing is bs', () => {
    const [c] = run(log([[100.2, 'by=5 p1d=300 p1r=150 bm=attack bs=0.4']]));
    assert.deepStrictEqual([c.mode, c.snapMode, c.swing], ['attack', 'laning', 0.4]);
});

test('steals: the snapshot mode is the latest at or before the whole second of the death', () => {
    // pid 5 snaps every 10 s from t=1 (mode laning from t=51), plus one at 60.5 in mode 'late' (before the t=61 snap): a death at 60.9 is read at second 60,
    // so it sees the t=51 snap, not the one at 60.5; 50.9 sees the t=41 snap.
    const extra = [line(60.5, 'snap pid=5 x=0 y=0 alive=1 mode=late')];
    const cases = run(log([[50.9, 'by=5 p1d=100 p1r=150'], [60.9, 'by=5 p1d=100 p1r=150']], { extra }));
    assert.deepStrictEqual(cases.map(c => c.snapMode), ['idle', 'laning']);
});

test('steals: only deaths before until count', () => {
    const g = log([[100, 'by=5 p1d=100 p1r=150'], [299.9, 'by=5 p1d=100 p1r=150'], [300, 'by=5 p1d=100 p1r=150']]);
    assert.deepStrictEqual(run(g, 300).map(c => c.t), [100, 299.9]);
    assert.strictEqual(run(g, 600).length, 3);
});

test('steals: no ev=creep_death, or no trusted lineup, gives undefined, not zero cases', () => {
    assert.strictEqual(run(log([])), undefined, 'no deaths');
    assert.deepStrictEqual(run(log([[100, 'by=1 p1d=50 p1r=150']])), [], 'deaths and a lineup, none a steal: zero cases');
    const death = [[100, 'by=5 p1d=100 p1r=150']];
    assert.strictEqual(run(log(death, { drop: 2 })), undefined, 'four heroes of the team: positions are not 1-5');
    const human = [line(0, 'player pid=9 hero=axe team=2 human=1'), line(1, 'snap pid=9 x=0 y=0 alive=1')];
    assert.strictEqual(run(log(death, { extra: human })), undefined, 'a human on the team has no position, so the team has none');
    const twice = log(death).replace('pos=4', 'pos=5');
    assert.strictEqual(run(twice), undefined, 'two heroes at pos5, none at 4');
});

test('steals: a hero without any located snap is not counted in the lineup', () => {
    const noSnap = [line(0, 'bot pid=8 hero=h8 team=2 pos=3')];
    assert.strictEqual(run(log([[100, 'by=5 p1d=100 p1r=150']], { extra: noSnap })).length, 1);
});

test('steals: the last ev=bot position of a hero wins (a role change re-emits it)', () => {
    const re = [line(20, 'bot pid=5 hero=h5 team=2 pos=4'), line(21, 'bot pid=4 hero=h4 team=2 pos=5')];
    const [c] = run(log([[100, 'by=5 p1d=100 p1r=150']], { extra: re }));
    assert.strictEqual(c.pos, 4);
});

test('steals: a log with two games reads one game at a time; an unknown game throws', () => {
    const one = log([[100, 'by=5 p1d=100 p1r=150']]);
    const two = one + '\n' + log([[100, 'by=4 p1d=100 p1r=150'], [110, 'by=4 p1d=100 p1r=150']]);
    assert.deepStrictEqual(run(two, 600, 1).map(c => c.pid), [5]);
    assert.deepStrictEqual(run(two, 600, 2).map(c => c.pid), [4, 4]);
    assert.throws(() => run(two, 600, 3), /not in the store/);
});

test('steals: the query equals dynamic.js auditedSteals on a parsed log', () => {
    const text = log([
        [100.2, 'by=5 p1d=300 p1r=150 bm=attack bs=0.4'], [110, 'by=4 p1d=900 p1r=150 p1t=1'], [120, 'by=5 p1d=301 p1r=150'],
        [130, 'by=5'], [140, 'by=1 p1d=50 p1r=150'], [170, 'by=4 p2d=100 p2r=150 p3d=900 p3r=150 p3t=0'], [610, 'by=5 p1d=50 p1r=150'],
    ]);
    const { parseLog } = require('../parse');
    const strip = o => JSON.parse(JSON.stringify(o));
    /** dynamicMetrics' lpos for the log text, through an in-memory store as nf.js reads it. */
    const lposOf = t => {
        const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-steals-')), 'a.log');
        fs.writeFileSync(f, t + '\n');
        const s = new Store(':memory:');
        s.ingest(f);
        s.refreshViews();
        const lpos = D.dynamicMetrics(s, f, 1).lpos;
        s.db.close();
        return lpos;
    };
    const want = (t, until = 600) => { const g = parseLog(t)[0]; return D.auditedSteals(g, D.series(g), lposOf(t), until); };
    assert.ok(want(text).length > 0);
    assert.deepStrictEqual(strip(run(text)), strip(want(text)));
    // The lineup trust rule too: dynamicMetrics' lpos and the query's lineup agree on a team that is not trusted.
    const four = log([[100, 'by=5 p1d=100 p1r=150']], { drop: 2 });
    assert.strictEqual(want(four), undefined);
    assert.strictEqual(run(four), undefined);
});
