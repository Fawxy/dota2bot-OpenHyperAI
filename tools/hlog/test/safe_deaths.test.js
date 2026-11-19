'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { mapLeave, deathsFromSnaps, stateAt } = require('../safe_deaths');

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
