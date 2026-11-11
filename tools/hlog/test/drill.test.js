'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const q = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

function run(lines, name, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-drill-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(q(name), params);
    s.db.close();
    return out;
}

const snap = (t, pid, o = {}) => line(t, `snap pid=${pid} x=${o.x ?? 0} y=${o.y ?? 0} alive=1 hp=${o.hp ?? 100} mp=50 lvl=1 lh=${o.lh ?? 0} dn=${o.dn ?? 0} kills=0 deaths=${o.deaths ?? 0} mode=${o.mode ?? 'laning'}${o.tgt ? ` tgt=${o.tgt}` : ''} d=0.3 act=2 gold=600`);
const role = (pid, team, pos, r, name = 'lane-spot-statue') => line(0.5, `drill ph=role name=${name} pid=${pid} team=${team} pos=${pos} role=${r}`);
const rep = (t, n, input = 'on', extra = '', name = 'lane-spot-statue') => line(t, `drill ph=rep name=${name} team=2 rep=${n} input=${input} start=${Math.floor(t / 30) * 30}${extra}`);

test('drill: one row per rep and cast hero, with what the hero gained and lost in the rep', () => {
    const out = run([
        role(0, 2, 1, 'cast'), role(7, 3, 3, 'statue'), role(4, 2, 5, 'bench'),
        rep(1, 1), rep(31, 2),
        snap(1, 0), snap(10, 0, { hp: 90, lh: 1 }), snap(20, 0, { hp: 95, lh: 2, dn: 1 }), snap(29, 0, { hp: 80, lh: 2, dn: 1 }),
        snap(32, 0, { hp: 80, lh: 3, dn: 1 }), snap(50, 0, { hp: 70, lh: 4, dn: 1 }),
        // A rep opened as the game stops (under 5 s) is dropped.
        rep(61, 3), snap(62, 0, { hp: 70, lh: 4, dn: 1 }),
        // The statue's snapshots are not a cast hero's.
        snap(10, 7, { hp: 10 }),
    ], 'drill');
    assert.strictEqual(out.length, 2);
    assert.deepStrictEqual([out[0].rep, out[0].pid, out[0].pos, out[0].input, out[0].start, out[0].stop], [1, 0, 1, 'on', 0, 30]);
    assert.strictEqual(out[0].lh, 2);
    assert.strictEqual(out[0].dn, 1);
    // Drops 100->90 and 95->80; the heal to 95 does not cancel them.
    assert.strictEqual(out[0].hp_lost, 25);
    assert.strictEqual(out[0].results, null);
    // The second rep ends at the third's start.
    assert.strictEqual(out[1].stop, 60);
    assert.strictEqual(out[1].hp_lost, 10);
});

test('drill: a stack drill counts the stack lines in each rep, control reps marked off', () => {
    const out = run([
        role(4, 2, 5, 'cast', 'stack'),
        line(120.2, 'drill ph=rep name=stack team=2 rep=1 input=on start=120 forces=stack'),
        line(180.1, 'drill ph=rep name=stack team=2 rep=2 input=off start=180 forces=stack'),
        snap(121, 4), snap(240, 4),
        line(173, 'stack pid=4 min=2 res=stacked why=ok'),
        line(233, 'stack pid=4 min=3 res=miss why=early'),
    ], 'drill', { name: 'stack' });
    assert.deepStrictEqual(out.map(r => [r.rep, r.input, r.results, r.ok]), [[1, 'on', 1, 1], [2, 'off', 1, 0]]);
});

test('drill_roles: each hero\'s role, its attack-target samples and farm share', () => {
    const out = run([
        role(0, 2, 1, 'cast'), role(7, 3, 3, 'statue'),
        snap(1, 0, { tgt: 'npc_dota_creep_badguys_melee' }), snap(2, 0),
        snap(1, 7, { mode: 'farm', x: 100 }), snap(2, 7, { mode: 'farm', x: 140 }),
    ], 'drill_roles');
    const by = Object.fromEntries(out.map(r => [r.pid, r]));
    assert.strictEqual(by[0].role, 'cast');
    assert.strictEqual(by[0].tgt, 1);
    assert.strictEqual(by[7].role, 'statue');
    assert.strictEqual(by[7].tgt, 0);
    assert.strictEqual(by[7].farm, 1);
    assert.strictEqual(by[7].x, 120);
});

test('drill on a rig: reps that never reached ready are dropped, ready n of m and the release second are kept', () => {
    const name = 'retreat-heal-items';
    const ready = (t, n, ok, v, fail = '') => line(t, `drill ph=ready name=${name} pid=4 rep=${n} var=${v} ok=${ok}${fail ? ` fail=${fail}` : ''} secs=${t % 150} hp=0.25`);
    const rrep = (t, n, v) => line(t, `drill ph=rep name=${name} team=2 rep=${n} input=on start=${t} var=${v}`);
    const lines = [
        role(4, 2, 5, 'cast', name), role(7, 3, 3, 'actor', name),
        rrep(60, 1, 'salve'), rrep(210, 2, 'tango'), rrep(360, 3, 'stays'),
        ready(100, 1, 1, 'salve'), ready(320, 2, 0, 'tango', 'holds'), ready(400, 3, 1, 'stays'),
        snap(61, 4), snap(100, 4, { hp: 25, mode: 'farm' }), snap(110, 4, { hp: 20, mode: 'retreat' }), snap(209, 4, { mode: 'retreat' }),
        snap(211, 4, { mode: 'farm' }), snap(330, 4, { mode: 'farm' }), snap(401, 4, { mode: 'retreat' }), snap(420, 4, { mode: 'retreat' }),
    ];
    const out = run(lines, 'drill');
    assert.deepStrictEqual(out.map(r => [r.rep, r.var, r.released, r.ready_n, r.ready_m]), [[1, 'salve', 100, 2, 3], [3, 'stays', 400, 2, 3]]);
    // Rep 1 is graded from its release (100): the setup's drop to 25% before it is not hp_lost; the drop to 20% after is.
    assert.strictEqual(out[0].hp_lost, 5);
    const roles = run(lines, 'drill_roles');
    const cast = roles.find(r => r.pid === 4);
    // The ready second itself is the last setup frame (farm); after it only retreat, and rep 2 (invalid, farm) adds nothing.
    assert.strictEqual(cast.rel_modes, 'retreat');
    assert.strictEqual(roles.find(r => r.pid === 7).rel_modes, null);
});

test('drill without ready lines keeps every rep (drills built before rigs)', () => {
    const out = run([role(0, 2, 1, 'cast'), rep(1, 1), rep(31, 2), snap(1, 0), snap(29, 0), snap(32, 0), snap(50, 0)], 'drill');
    assert.deepStrictEqual(out.map(r => [r.rep, r.ready_m]), [[1, null], [2, null]]);
});
