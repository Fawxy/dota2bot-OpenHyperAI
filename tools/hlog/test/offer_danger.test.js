'use strict';
// The danger shadow (queries/offer_danger.sql): one row per begun offer with a place, its parts beside the HP lost to heroes in
// its window and a death within the window plus 5 s. One game, pid 1 (pos 1):
//   begin at 100, bsec 4, one reacher: hero 10 at 101, creep 10 at 102, hero+creep 10 at 103 (hero's share 5), hero 10 at 106
//     (past the window): hero_loss 15, loss 30, no death;
//   begin at 200, bsec 3: a hero's hit of 50 at 201, then dead (seen at the next live snapshot): hero_loss 50, died 1;
//   a begin with no place (no bsec) and a decider line with no begin are not rows.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const snap = (t, hp, extra, deaths = 0) =>
    line(t, `snap pid=1 x=0 y=-2500 alive=1 hp=${hp} hv=${hp * 6} deaths=${deaths} hit=0 hc=0 ht=0 ah=0 ac=0 an=0 at=0 ${extra || ''}`);

function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-offer-danger-'));
    const file = path.join(dir, '2026-11-27T00-00-00-od1_A_onrad_1.log');
    const lines = [
        line(-90, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(100, 'choice pid=1 kind=decider held=pull win=farm hs=hard beg=pull btgt=camp:3 bpx=100 bpy=-200 bsec=4 dn=1 dre=10:300:0.5:120 dbu=0.2 dal=0 dtw=0 dun=11:40:2500'),
        snap(100, 100), snap(101, 90, 'hit=1 ah=1'), snap(102, 80, 'hc=1 ac=2'), snap(103, 70, 'hit=1 hc=1 ah=1 ac=1'),
        snap(104, 70), snap(105, 70), snap(106, 60, 'hit=1 ah=1'),
        line(150, 'choice pid=1 kind=decider held=- win=laning'),
        line(160, 'choice pid=1 kind=decider held=stack win=farm hs=hard beg=stack btgt=camp:3'),
        line(200, 'choice pid=1 kind=decider held=creep win=farm hs=hard beg=creep btgt=creep:7 bsec=3 dn=0 dbu=0 dal=1 dtw=1'),
        snap(200, 100), snap(201, 50, 'hit=1 ah=1'), snap(215, 100, '', 1),
    ];
    fs.writeFileSync(file, lines.join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}

test('offer_danger: each begun offer with a place, its parts beside the HP lost to heroes and a death in its window', () => {
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'offer_danger.sql'), 'utf8');
    const rows = load().query(sql, { like: '%od1%' }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.t, r.beg, r.pos, r.bsec, r.dn, r.dre, r.dun, r.dtw, r.hero_loss, r.loss, r.died]), [
        [100, 'pull', 1, 4, 1, '10:300:0.5:120', '11:40:2500', 0, 15, 30, 0],
        [200, 'creep', 1, 3, 0, null, null, 1, 50, 50, 1],
    ]);
});
