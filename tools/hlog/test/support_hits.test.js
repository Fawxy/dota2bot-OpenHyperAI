'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'support_hits.sql'), 'utf8');

function rows(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-suph-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

test('a support row splits its last-hit attempts by claim, counts denies, reads its counters at the last snap before until; a core gets no row', () => {
    const out = rows([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(100, 'lh pid=5 kind=lasthit result=ok reason=ok ranged=0 eta=0 contested=0 walk=0 dies=1 claim=busy'),
        line(110, 'lh pid=5 kind=lasthit result=fail reason=missed ranged=0 eta=0 contested=0 walk=0 dies=1 claim=busy'),
        line(120, 'lh pid=5 kind=lasthit result=ok reason=ok ranged=1 eta=0 contested=0 walk=0 dies=1 claim=free'),
        line(130, 'lh pid=5 kind=deny result=ok reason=ok ranged=0 eta=0 contested=0 walk=0 dies=1 claim=deny'),
        line(140, 'lh pid=5 kind=deny result=fail reason=missed ranged=0 eta=0 contested=0 walk=0 dies=1 claim=deny'),
        line(140, 'lh pid=1 kind=lasthit result=ok reason=ok ranged=0 eta=0 contested=0 walk=0 dies=1'),
        line(590, 'snap pid=5 x=0 y=0 lh=4 dn=2'),
        line(700, 'lh pid=5 kind=lasthit result=ok reason=ok ranged=0 eta=0 contested=0 walk=0 dies=1 claim=free'),
        line(700, 'snap pid=5 x=0 y=0 lh=9 dn=3'),
    ]);
    assert.strictEqual(out.length, 1, 'only the support');
    const r = out[0];
    assert.deepStrictEqual([r.pos, r.lh, r.dn, r.lh_n, r.lh_ok, r.busy_n, r.busy_ok, r.free_n, r.free_ok, r.dn_n, r.dn_ok],
        [5, 4, 2, 3, 2, 2, 1, 1, 1, 2, 1]);
});
