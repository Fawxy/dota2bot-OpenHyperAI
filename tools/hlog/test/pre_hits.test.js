'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pre_hits.sql'), 'utf8');

function rows(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ph-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

test('last hits per pre-hit count only landed last hits on creeps the core pre-hit, per team, over pre-hits that fired', () => {
    const out = rows([
        line(0, 'bot pid=1 team=2 pos=1'),
        line(0, 'bot pid=2 team=2 pos=5'),
        line(0, 'bot pid=6 team=3 pos=2'),
        line(100, 'prehit pid=1 result=ok reason=ok'),
        line(101, 'lh pid=1 kind=lasthit result=ok reason=ok ph=1'),
        line(110, 'prehit pid=1 result=ok reason=ok'),
        line(111, 'lh pid=1 kind=lasthit result=fail reason=taken_by_other ph=1'),
        line(120, 'prehit pid=1 result=fail reason=no_target'),
        // A last hit on a creep not pre-hit does not count; nor does a support's (pos 5) line.
        line(130, 'lh pid=1 kind=lasthit result=ok reason=ok'),
        line(131, 'lh pid=2 kind=lasthit result=ok reason=ok ph=1'),
        line(140, 'prehit pid=6 result=fail reason=missed'),
        line(700, 'prehit pid=1 result=ok reason=ok'),
    ]);
    assert.strictEqual(out.length, 2);
    const [r, d] = out;
    assert.deepStrictEqual([r.team, r.n, r.fired, r.lost, r.tried_after, r.lh_after, r.lh_per_prehit], [2, 3, 2, 1, 2, 1, 0.5]);
    assert.deepStrictEqual([d.team, d.n, d.fired, d.missed, d.lh_after, d.lh_per_prehit], [3, 1, 0, 1, 0, null]);
});
