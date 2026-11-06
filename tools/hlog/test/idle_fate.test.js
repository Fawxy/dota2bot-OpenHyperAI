'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'idle_fate.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-if-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return Object.fromEntries(out.map(r => [r.kind, { ...r }]));
}

const sw = (pid, kind, cid, result = 'ok') => `idle_swing pid=${pid} kind=${kind} mode=safe n=0 cx=0 cy=0 result=${result} reason=ok ranged=0 walk=0 hp=100 hf=0.2 cid=${cid}`;

test('idle fate: each creep once by its id, its fate by killer', () => {
    const out = run([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=6 hero=h6 team=3 pos=1'),
        // predeny 10: both laners swing, pid 5 denies it: one creep, two swings, ours.
        line(100, sw(1, 'predeny', 10)),
        line(100.5, sw(5, 'predeny', 10)),
        line(102, 'own_creep_death team=2 kind=melee x=1000 y=0 hp=0.05 by=5 cid=10'),
        // predeny 11: no deny of ours; the Dire log's creep_death names their pid 6's last hit there: lost_hero.
        line(110, sw(1, 'predeny', 11)),
        line(112, 'own_creep_death team=2 kind=melee x=2000 y=0 hp=0.05 by=none cid=11'),
        line(112.2, 'creep_death team=3 kind=melee x=2010 y=0 hp=0.05 by=6 cid=99'),
        // predeny 12: no deny, no enemy hero: lost_other. predeny 13: no death logged: unmatched; a failed swing is no creep.
        line(120, sw(1, 'predeny', 12)),
        line(121, 'own_creep_death team=2 kind=melee x=3000 y=0 hp=0.05 by=none cid=12'),
        line(130, sw(1, 'predeny', 13)),
        line(131, sw(1, 'predeny', 14, 'fail')),
        // setup 20: our pid 1's last hit: ours. setup 21: their deny: lost_hero. setup 22: no hero: lost_other.
        line(140, sw(1, 'setup', 20)),
        line(142, 'creep_death team=2 kind=melee x=4000 y=0 hp=0.05 by=1 cid=20'),
        line(150, sw(1, 'setup', 21)),
        line(152, 'creep_death team=2 kind=melee x=5000 y=0 hp=0.05 by=deny cid=21'),
        line(160, sw(5, 'setup', 22)),
        line(162, 'creep_death team=2 kind=melee x=6000 y=0 hp=0.05 by=none cid=22'),
    ]);
    assert.deepStrictEqual(
        { creeps: out.predeny.creeps, swings: out.predeny.swings, ours: out.predeny.ours, lost_hero: out.predeny.lost_hero, lost_other: out.predeny.lost_other, unmatched: out.predeny.unmatched, rate: out.predeny.rate },
        { creeps: 4, swings: 5, ours: 1, lost_hero: 1, lost_other: 1, unmatched: 1, rate: 0.25 });
    assert.deepStrictEqual(
        { creeps: out.setup.creeps, ours: out.setup.ours, lost_hero: out.setup.lost_hero, lost_other: out.setup.lost_other, rate: out.setup.rate },
        { creeps: 3, ours: 1, lost_hero: 1, lost_other: 1, rate: 0.33 });
});

test('idle fate: logs without creep ids give no rows', () => {
    const out = run([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(100, 'idle_swing pid=1 kind=predeny mode=safe n=0 cx=0 cy=0 result=ok reason=ok ranged=0 walk=0 hp=100 hf=0.2'),
    ]);
    assert.deepStrictEqual(out, {});
});
