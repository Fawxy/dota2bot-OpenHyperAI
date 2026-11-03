'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lane_waste.sql'), 'utf8');

function store(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lw-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}

// (0, 0) is on the mid lane; (-1454, -3357) is camp 3's spawn, off every lane.
const lines = [
    line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
    line(0, 'bot pid=4 hero=h4 team=2 pos=4'),
    line(0, 'bot pid=9 hero=h9 team=3 pos=5'),
    // tower beats a core that swung on it.
    line(100, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=1 p1d=300 p1r=150 p1t=1'),
    // core_on: the core was attacking it (p1a set, p1t 0).
    line(110, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=0 p1d=300 p1r=150 p1t=0 p1a=0.4'),
    // core_reach: at range + 300 exactly, not on it; it beats a support in reach.
    line(120.5, 'snap pid=5 x=100 y=0 alive=1 ar=600'),
    line(121, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=0 p1d=450 p1r=150 p1t=0'),
    // sup_reach: core beyond reach; pos 4's snap 0.5 s before is at its ar + 300, pos 5's is far.
    line(130.5, 'snap pid=4 x=900 y=0 alive=1 ar=600'),
    line(130.6, 'snap pid=5 x=3000 y=0 alive=1 ar=600'),
    line(131, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=0 p1d=451 p1r=150 p1t=0'),
    // no_reach: the support's only snap near is 1.6 s old, and a dead support's snap does not count.
    line(139.4, 'snap pid=4 x=0 y=0 alive=1 ar=600'),
    line(140.5, 'snap pid=5 x=0 y=0 alive=0 ar=600'),
    line(141, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=0 p1d=1200 p1r=150 p1t=0'),
    // camp: 600 from camp 13's spawn, no pull logged, no one in reach, no core logged.
    line(150, 'creep_death team=2 kind=ranged x=-2415 y=-7802 hp=0.05 by=none tw=0'),
    // no_reach, not camp: 601 from the spawn.
    line(160, 'creep_death team=2 kind=ranged x=-2415 y=-7801 hp=0.05 by=none'),
    // pulled: the other team's ok pull of camp 13 (slot 170), death 30 s on and 799 from the spawn; it beats a core in reach.
    line(165, 'pull_job pid=9 pos=5 lane=3 camp=13 slot=170 res=ok why=ok'),
    line(200, 'creep_death team=2 kind=melee x=-2415 y=-7603 hp=0.05 by=none tw=0 p1d=400 p1r=150 p1t=0'),
    // our own team's pull, and a failed pull of theirs, are not the other team's pull: core_reach.
    line(205, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=210 res=ok why=ok'),
    line(206, 'pull_job pid=9 pos=5 lane=3 camp=13 slot=211 res=fail why=cancelled:empty'),
    line(212, 'creep_death team=2 kind=melee x=-2415 y=-7603 hp=0.05 by=none tw=0 p1d=400 p1r=150 p1t=0'),
    // our last hit is not waste, but is a death.
    line(220, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=1 tw=0 p1d=100 p1r=150 p1t=1'),
    line(700, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=1'),
];

test('each no-one death gets the first cause that holds: tower, core_on, pulled (the other team\'s ok pull, 0-30 s, within 800), core_reach, sup_reach (a live snap within 1.5 s), camp (within 600), no_reach', () => {
    const s = store(lines);
    const v = s.query('SELECT t, cause, core FROM lane_waste ORDER BY t');
    assert.deepStrictEqual(v.map(r => [r.t, r.cause]), [
        [100, 'tower'], [110, 'core_on'], [121, 'core_reach'], [131, 'sup_reach'], [141, 'no_reach'],
        [150, 'camp'], [160, 'no_reach'], [200, 'pulled'], [212, 'core_reach'], [700, 'tower'],
    ]);
    assert.strictEqual(v.find(r => r.t === 141).core, 'near');
    assert.strictEqual(v.find(r => r.t === 160).core, 'none');
    const [r] = s.query(sql, {});
    s.db.close();
    assert.deepStrictEqual([r.deaths, r.waste, r.tower, r.core_on, r.pulled, r.core_reach, r.sup_reach, r.camp, r.no_reach, r.nr_core_near, r.untagged],
        [10, 9, 1, 1, 1, 2, 1, 1, 2, 1, 1], 'until 600 drops t=700; the t=160 death has no tw');
});

test('the camp table equals camp_boxes.json spawn points', () => {
    const view = fs.readFileSync(path.join(__dirname, '..', 'views', 'lane_waste.sql'), 'utf8');
    const got = [...view.slice(view.indexOf('camps(idx, x, y)'), view.indexOf('),\nd AS')).matchAll(/\((\d+), (-?\d+), (-?\d+)\)/g)]
        .map(m => [m[1], +m[2], +m[3]]);
    const want = Object.entries(require('../camp_boxes.json')).map(([k, b]) => [k, b.x, b.y]);
    assert.deepStrictEqual(got, want);
});
