'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { mapLeave, deathsFromSnaps } = require('../safe_deaths');

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

test('a death is the last snap with hp above 0 before the counter rises, whatever the fountain snaps after it show', () => {
    const s = (t, hp, deaths, x = 0) => ({ pid: '1', t, x, y: 0, hp, deaths });
    const d = deathsFromSnaps([s(10, 50, 0), s(11, 20, 0), s(12, 0, 0), s(13, 5, 0, 6000), s(60, 100, 1, 6000)]);
    assert.deepEqual(d, [{ pid: '1', t: 11 }]);
});
