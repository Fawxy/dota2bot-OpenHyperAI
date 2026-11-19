'use strict';
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { mapLeave, mapSafe, deathsFromSnaps, stateAt, episodesOf, analyse } = require('../safe_deaths');
const { toLua } = require('../cut');
const { newState, doString, getGlobal } = require('../../../tests/humaniser/harness');

const TOWERS = new Map([[3, '0,5000,5000,700,144']]);
// Our hero at the origin: speed 300, hull 24; `he` rows are pid,x,y,hp,range,hull,speed,atk,eng,e3,e6,illusion.
const cut = (he, extra = '') => ({ b: '0,0,500,600,150,24,300,0', he, ta: '7ff,7ff', tt: '', dt: '0', ...Object.fromEntries(extra.split(' ').filter(Boolean).map((kv) => kv.split('='))) });

test('a hero reaches us within 2 s of its run plus both ranges and hulls, a hero just past that does not, an illusion never', () => {
    // reach = 300 x 2 + 600 + 24 + 24 = 1248
    const edge = mapLeave(cut('7,1200,0,500,600,24,300,0,0,100,300,0;8,1300,0,500,600,24,300,0,0,100,300,0;9,10,0,500,600,24,300,0,0,100,300,1'), TOWERS, 2);
    assert.deepEqual(edge.inputs.reach.map((r) => r.pid), [7]);
    assert.equal(edge.n, 1);
});

test('a hero that hit us in the last second counts its 6 s damage, one that did not its 2 s damage', () => {
    const m = mapLeave(cut('7,500,0,500,600,24,300,0,1,100,300,0;8,500,0,500,600,24,300,0,0,100,300,0'), TOWERS, 2);
    assert.deepEqual(m.inputs.reach.map((r) => [r.pid, r.hitting, r.dmg]), [[7, true, 300], [8, false, 100]]);
});

test('the tower is a standing enemy tower within its range plus hull; a tower out of the mask does not count; a tower aimed at us is on us', () => {
    const near = new Map([[3, '0,500,0,700,144']]);
    assert.equal(mapLeave(cut(''), near, 2).inputs.tower, true);
    assert.equal(mapLeave(cut(''), near, 2).inputs.tower, true);
    assert.equal(mapLeave({ ...cut(''), ta: '7ff,2' }, near, 2).inputs.tower, false);
    assert.equal(mapLeave(cut(''), TOWERS, 2).inputs.tower, false);
    assert.equal(mapLeave({ ...cut(''), tt: '3,0,b' }, TOWERS, 2).inputs.towerOnMe, true);
    assert.equal(mapLeave({ ...cut(''), tt: '2,0,b' }, TOWERS, 2).inputs.towerOnMe, false);
});

const snap = (pid, t, deaths, x = 0, hp = 100) => ({ pid, t, x, y: 0, hp, deaths });
const times = (d) => d.map((v) => [v.pid, v.t]);

test('a hero that teleports alive and dies 150 s later is dated at the death, not the teleport', () => {
    const base = [snap('1', 10, 0), snap('1', 11, 0, 5000), snap('1', 160, 0, 5000), snap('1', 161, 0, 5000, 20), snap('1', 190, 1, 0)];
    assert.deepEqual(times(deathsFromSnaps(base)), [['1', 161]]);
    // control: the same jump with no counter rise is no death
    assert.deepEqual(deathsFromSnaps(base.map((s) => ({ ...s, deaths: 0 }))), []);
});

test('two deaths of one hero are each dated at their own gap', () => {
    const l = [snap('1', 10, 0), snap('1', 11, 0), snap('1', 40, 1), snap('1', 41, 1), snap('1', 90, 1), snap('1', 91, 1), snap('1', 120, 2)];
    assert.deepEqual(times(deathsFromSnaps(l)), [['1', 11], ['1', 91]]);
    // another hero's counter does not leak in
    assert.deepEqual(times(deathsFromSnaps([...l, snap('2', 10, 0), snap('2', 60, 0)])), [['1', 11], ['1', 91]]);
});

test('a snapshot gap with no rise in the deaths counter is not a death', () => {
    assert.deepEqual(deathsFromSnaps([snap('1', 10, 0), snap('1', 11, 0), snap('1', 60, 0), snap('1', 61, 0)]), []);
});

test('a counter rise seen only at the first snapshot after respawn is dated before the gap', () => {
    const d = deathsFromSnaps([snap('1', 20, 0), snap('1', 21, 0, 0, 30), snap('1', 45, 1, 6000, 100), snap('1', 46, 1, 6000)]);
    assert.deepEqual(times(d), [['1', 21]]);
});

test('state at a death: not held after an arb end, else a running retreat with its why, else read running', () => {
    const ev = [
        { kind: 'retreat', ph: 'start', pid: '1', t: 10, why: 'lethal' },
        { kind: 'retreat', ph: 'end', pid: '1', t: 20 },
        { kind: 'retreat', ph: 'start', pid: '1', t: 30, why: 'tower' },
        { kind: 'arbEnd', pid: '2', t: 5 },
        { kind: 'retreat', ph: 'start', pid: '2', t: 6, why: 'x' },
    ];
    assert.deepEqual(stateAt(ev, '1', 15), { state: 'retreat', why: 'lethal' });
    assert.deepEqual(stateAt(ev, '1', 25), { state: 'read' });
    assert.deepEqual(stateAt(ev, '1', 35), { state: 'retreat', why: 'tower' });
    assert.deepEqual(stateAt(ev, '2', 35), { state: 'notheld' });
});

const parse = (line) => Object.fromEntries(line.split(' ').map((kv) => kv.split('=')));

test('a kind=safe line maps to the inputs the cut.js safe driver feeds Safe.Decide: same answer, unseen reachers, tower and hold included', () => {
    const lines = [
        'hpa=584 hpm=730 rr=7,1,201,0;5,1,310,0 mi=0 stw=0,0 ld=73,0,0 awy=0 hld=1 hd=0',
        'hpa=300 hpm=730 rr=7,0,400,1 mi=0.4 stw=1,1 ld=10,20,30 awy=1 hld=0 hd=1',
        'hpa=730 hpm=730 mi=0 stw=0,0 ld=0,0,0 awy=0 hld=0 hd=0',
    ].map(parse);
    const L = newState();
    const driver = path.resolve(__dirname, '../../../tests/humaniser/fixture_drivers/safe.lua');
    let err = doString(L, `dofile(HARNESS_DIR .. "/dota_stubs.lua")\nFreshHumaniser({ Enable = true })\nSAFE = require("bots/FunLib/humaniser/safe")\nDRIVER = dofile(${JSON.stringify(driver)})`);
    assert.equal(err, null);
    const seen = new Set();
    for (const cut of lines) {
        const world = { hpa: Number(cut.hpa), hpm: Number(cut.hpm), mi: Number(cut.mi), awy: Number(cut.awy), hld: Number(cut.hld), hd: Number(cut.hd), rr: cut.rr, stw: cut.stw, ld: cut.ld };
        err = doString(L, `local fx = { world = ${toLua(world)} }
local a = SAFE.Decide(${toLua(mapSafe(cut).inputs)})
local d = DRIVER(fx).actions[1]
OUT = a.level .. "(" .. a.reason .. ")" .. "|" .. d.verb .. "(" .. d.target .. ")"`);
        assert.equal(err, null);
        const [mine, theirs] = String(getGlobal(L, 'OUT')).split('|');
        assert.equal(mine, theirs);
        seen.add(mine);
    }
    assert.ok(seen.size > 1, 'the lines must not all give one answer');
    assert.equal(mapSafe(lines[0]).n, 2);
    assert.equal(mapSafe(lines[2]).n, 0);
    assert.equal(mapSafe(lines[1]).inputs.reach[0].unseen, true);
});

const answers = (deadlyAt) => Object.fromEntries(['1', '1.25', '1.5', '2'].map((b) => [b, { level: deadlyAt.includes(b) ? 'deadly' : 'safe', reason: 'kill', kill: 0 }]));
const ROW = { n: 1, kill0: 100, pos: '3', inputs: { hp: 500, hpMax: 500 } };
const row = (t, retreat, deadlyAt, extra = {}) => ({ ...ROW, file: 'f', pid: '1', t, retreat, dec: retreat ? 'threat' : 'stay', answers: answers(deadlyAt), ...extra });
const game = (rows, extra = {}) => ({ rows, deaths: [], episodes: [], snaps: new Map(), ...extra });

test('table 4 puts each moment in one of four cells by the bar and the hero\'s retreat, and the HP lost and death follow that moment', () => {
    // 1.0 is deadly at the first two rows only; the hero retreats on the first and third. Each row weighs 2 s.
    const rows = [row(0, true, ['1']), row(2, false, ['1']), row(4, true, []), row(6, false, []), row(8, false, [])];
    // the hero drops to 40% after the second row (stayed where the bar says leave) and dies at 4.5
    const snaps = new Map([['1', [{ t: 3, hp: 50 }, { t: 4, hp: 40 }]]]);
    const res = analyse([game(rows, { snaps, deaths: [{ pid: '1', t: 4.5 }] })], true);
    const cell = (c) => res.t4[`all\t1\t${c}`];
    assert.deepEqual(['DR', 'DN', 'SR', 'SN'].map((c) => cell(c).sec), [2, 2, 2, 2]);
    // a death inside the 5 s loses the whole start HP (1.0) for the moments before it
    assert.deepEqual(['DR', 'DN', 'SR', 'SN'].map((c) => cell(c).lost), [2, 2, 2, 0]);
    // control: the same rows with the retreat flags swapped move the seconds across the cells
    const flipped = analyse([game(rows.map((r) => ({ ...r, retreat: !r.retreat })))], true);
    const f = (c) => flipped.t4[`all\t1\t${c}`];
    assert.deepEqual([f('DR').sec, f('DN').sec, f('SR').sec, f('SN').sec], [2, 2, 2, 2]);
    assert.equal(f('DR').n, 1);
    assert.equal(f('DN').n, 1);
    assert.equal(f('DN').lostSec, 0, 'no snapshots in the window: left out of the HP column');
});

test('an episode counts as one a bar would not have begun only when the bar does not call its start moment deadly', () => {
    const rows = [row(10, false, ['1']), row(11, true, ['1']), row(30, false, [])];
    const ev = [
        { kind: 'retreat', ph: 'start', pid: '1', t: 10.5, why: 'threat' },
        { kind: 'retreat', ph: 'end', pid: '1', t: 14, res: 'gone', secs: 3.5, hpl: 0.2 },
        { kind: 'retreat', ph: 'start', pid: '1', t: 60, why: 'threat' },
        { kind: 'retreat', ph: 'end', pid: '1', t: 62, res: 'gone', secs: 2, hpl: 0 },
    ];
    const res = analyse([game(rows, { episodes: episodesOf(ev), deaths: [{ pid: '1', t: 14.5 }] })], true);
    assert.equal(res.t5.all.n, 2);
    assert.equal(res.t5.all.noLine, 1, 'the second episode has no source line in the 2.5 s before it');
    assert.deepEqual([res.t5.bar['1'].began, res.t5.bar['1'].not], [1, 0]);
    const b = res.t5.bar['1.25'];
    assert.deepEqual([b.began, b.not, b.notDied, b.notHpl, b.notLen], [0, 1, 1, [0.2], [3.5]]);
});
