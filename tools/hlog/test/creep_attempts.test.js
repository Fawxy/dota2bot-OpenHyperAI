'use strict';
// The creep row's attempts (queries/creep_attempts.sql, creep_attempt_rows.sql, fragment creep_attempt_rows). A synthetic game:
// Radiant sniper (pid 2, pos 2, range 550). Each attempt is a job start and end; the creep's death is the hero's team's creep_death
// of the attempt's cid, its p2* fields the sniper's distance, range and target then.
// A1 100  landed (why ok)
// A2 120  cut by retreat after the hero was in range (tin 0.4 of a 1.0 s attempt)
// A3 140  cut by attack before it was (tin -1)
// A4 160  lost, the sniper attacking the creep as it died (p2t=1)
// A5 180  lost, at 560 of range 550 (inside range + 48), not attacking it
// A6 200  lost, at 900: out of range
// A7 220  an old line pair with no cid: the creep row's go=1 choice line names it (slot + gat = the start); the death at 590
// A8 402  lost with no death joined (the creep's death is 9 s past the end); the sniper dies at 405, within 5 s of the end
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const start = (t, cid, gw = 0.5) => line(t, `job pid=2 job=creep phase=start why=trigger host=17${cid === undefined ? '' : ` cid=${cid} gw=${gw} gd=1.2 rng=550`}`);
const end = (t, why, o = {}) => line(t, `job pid=2 job=creep phase=end why=${why} host=17` + (o.cut ? ` cut=${o.cut}` : '') +
    (o.old ? '' : ` cid=${o.cid} tin=${o.tin ?? -1}${o.sw === undefined ? '' : ` sw=${o.sw}`} hp0=${o.hp0 ?? 600} hp1=${o.hp1 ?? 600} msg="w=1.00 why=range d=40"`));
const death = (t, cid, d, tg = 0) => line(t, `creep_death team=2 kind=ranged x=0 y=0 hp=0.05 by=none tw=0 cid=${cid} p2d=${d} p2r=550 p2t=${tg} p2a=0.3`);
const snap = (t, o = {}) => line(t, `snap pid=2 x=0 y=0 alive=1 hp=${o.hp ?? 90} hv=${o.hv ?? 540} ar=550 deaths=${o.deaths ?? 0}`);

function gameLines() {
    const out = [line(-90, 'bot pid=2 hero=sniper team=2 pos=2')];
    for (let t = 90; t <= 405; t += 1) out.push(snap(t));
    out.push(snap(430, { deaths: 1 }));
    out.push(
        start(100, 1), end(101, 'ok', { cid: 1, tin: 0.3, sw: 1, hp0: 600, hp1: 590 }), death(100.9, 1, 500),
        start(120, 2), end(121, 'preempted', { cid: 2, cut: 'retreat', tin: 0.4, hp0: 600, hp1: 500 }), death(122, 2, 700),
        start(140, 3), end(141, 'preempted', { cid: 3, cut: 'attack' }),
        start(160, 4), end(161, 'taken_by_other', { cid: 4, tin: 0, sw: 1 }), death(160.9, 4, 500, 1),
        start(180, 5), end(181, 'denied', { cid: 5, tin: 0.2, sw: 0 }), death(180.9, 5, 560),
        start(200, 6), end(201, 'taken_by_other', { cid: 6, sw: 0 }), death(200.9, 6, 900),
        start(220, undefined), end(221, 'denied', { old: true }), death(220.9, 7, 590),
        line(221.5, 'choice pid=2 kind=creep go=1 want=1 src=own lane=2 slot=219.5 cid=7 ck=r who=t walk=0.8 gat=0.5 gw=0.8'),
        start(402, 8), end(403, 'timeout', { cid: 8, sw: 0 }), death(412, 8, 500),
    );
    return out;
}

function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-creep-attempts-'));
    const file = path.join(dir, '2026-11-25T00-00-00-ca_A_on_1.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(file, gameLines().sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}
const sqlOf = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');
const like = '%ca_A_on_1%';

test('creep_attempt_rows: each attempt classed by its end, the creep\'s death and the hero\'s swing', () => {
    const rows = load().query(sqlOf('creep_attempt_rows'), { like }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.t0, r.cid, r.cls, r.cut, r.arr, r.swon, r.died]), [
        [100, 1, 'landed', null, null, 0, 0],
        [120, 2, 'cut', 'retreat', 'after', 0, 0],
        [140, 3, 'cut', 'attack', 'before', null, 0],
        [160, 4, 'lost_swing', null, null, 1, 0],
        [180, 5, 'lost_inrange', null, null, 0, 0],
        [200, 6, 'lost_out', null, null, 0, 0],
        [220, 7, 'lost_inrange', null, null, 0, 0],
        [402, 8, 'lost_nodeath', null, null, null, 1],
    ]);
    const by = Object.fromEntries(rows.map(r => [r.t0, r]));
    assert.strictEqual(by[120].hplost, 100, 'HP lost from the end line');
    assert.strictEqual(by[220].hplost, 0, 'an old line pair reads HP from the snapshots');
    assert.strictEqual(by[220].gw, 0.8, 'an old line pair takes the walk at go from the choice line');
    assert.strictEqual(by[200].gap, 350, 'distance less range at the creep\'s death');
    assert.strictEqual(by[100].melee, 0);
});

test('creep_attempts: per game, class, cutting mode and arrival', () => {
    const rows = load().query(sqlOf('creep_attempts'), { like }).map(r => [r.cls, r.cut, r.arr, r.n, r.died]);
    assert.deepStrictEqual(rows, [
        ['landed', null, null, 1, 0],
        ['cut', 'attack', 'before', 1, 0],
        ['cut', 'retreat', 'after', 1, 0],
        ['lost_swing', null, null, 1, 0],
        ['lost_inrange', null, null, 2, 0],
        ['lost_out', null, null, 1, 0],
        ['lost_nodeath', null, null, 1, 1],
    ]);
});
