'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

test('arb disagree: seconds under the pick in force where its host is not the held mode, by pick, mode and desire branch', () => {
    const snap = (t, mode, by) => line(t, `snap pid=1 x=0 y=0 alive=1 mode=${mode} d=0.5 deaths=0 by="${by}"`);
    const arb = (t, pick, host, act, agree) => line(t, `arb pid=1 pick=${pick} grp=1 host=${host} act=${act} agree=${agree}`);
    const lines = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        arb(95, 'lane', 'laning', 'laning', 1),
        snap(96, 'laning', 'laning 0.90 by raw'),
        // The pick moves to retreat while Valve keeps farm at its run value: three seconds of disagreement.
        arb(100, 'retreat', 'retreat', 'farm', 0),
        snap(100, 'farm', 'farm 1.10 by raw'),
        snap(101, 'farm', 'farm 1.10 by raw'),
        snap(102, 'farm', 'farm 1.10 by raw'),
        arb(103, 'retreat', 'retreat', 'retreat', 1),
        snap(103, 'retreat', 'retreat 0.95 by raw'),
        arb(104, 'oha', undefined, 'farm', 1),
        snap(104, 'farm', 'farm 0.60 by raw'),
        // A built-in mode has no mode file, so the snap's `by` names another mode: kept, with no desire or source.
        arb(110, 'lane', 'laning', 'evasive', 0),
        snap(110, 'evasive', 'retreat 0.40 by raw'),
        snap(111, 'evasive', ''),
        // The mode came back to the pick's host before the next arb line: the snap's mode decides, not the line's agree.
        snap(112, 'laning', 'laning 0.90 by raw'),
        arb(700, 'lane', 'laning', 'farm', 0),
        snap(700, 'farm', 'farm 1.10 by raw'),
    ];
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-arb-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'arb_disagree.sql'), 'utf8');
    const rows = q => s.query(sql, q).map(r => [r.pick, r.act, r.desire, r.src, r.secs, r.games]);
    assert.deepStrictEqual(rows({}), [['retreat', 'farm', 1.1, 'raw', 3, 1], ['lane', 'evasive', null, null, 2, 1]]);
    assert.deepStrictEqual(rows({ pos_lo: 4, pos_hi: 5 }), []);
    s.db.close();
});
