'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lh_swings.sql'), 'utf8');

function rows(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lhsw-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

test('a swing message unpacks to its fields and err = pred - lhp only for a creep alive at the landing; a held attempt keeps why and sw with no swing fields', () => {
    const out = rows([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(100, 'lh pid=1 kind=lasthit result=ok reason=ok ranged=0 eta=0.3 contested=1 ol=2 od=0 ow=1 walk=0 dies=1.2 msg="w=0.40 hp=65 pred=35 mine=59 t=0.51 m=0.19 obs=84 idps=42 ew=1 er=1 ec=0.12 oc=0.31 end=0 dt=0.70 fa=0.48 lhp=20 fg=0.160"'),
        line(110, 'lh pid=1 kind=deny result=fail reason=interrupted ranged=1 eta=1.4 contested=0 ol=0 od=1 ow=0 walk=1.1 dies=1.5 msg="w=0.80 why=range d=120 sw=1"'),
        // An older build's swing: no calibration fields, so fa, lhp, fg, obs, idps and err are NULL.
        line(120, 'lh pid=1 kind=lasthit result=fail reason=missed ranged=0 eta=0 contested=0 ol=1 od=0 ow=0 walk=0 dies=-1 msg="w=0.10 hp=60 pred=30 mine=55 t=0.50 m=0.19 end=4 dt=1.00"'),
        // Gone at the predicted landing (lhp 0): our own hit took it, so the prediction cannot be scored.
        line(130, 'lh pid=1 kind=lasthit result=ok reason=ok ranged=0 eta=0 contested=0 ol=1 od=0 ow=0 walk=0 dies=-1 msg="w=0.10 hp=60 pred=30 mine=55 t=0.50 m=0.19 obs=0 idps=0 end=0 dt=0.60 fa=0.5 lhp=0 fg=0.1"'),
        line(700, 'lh pid=1 kind=lasthit result=ok reason=ok ranged=0 eta=0 contested=0 ol=1 od=0 ow=0 walk=0 dies=-1 msg="w=0.10 hp=60 pred=30 mine=55 t=0.50 m=0.19 end=0 dt=0.60 fa=0.5 lhp=0 fg=0.1"'),
    ]);
    assert.strictEqual(out.length, 4, 'the attempt at 700 is past until');
    const [a, b, c, d] = out;
    assert.deepStrictEqual([a.swung, a.w, a.why, a.sw, a.hp, a.pred, a.mine, a.thit, a.m, a.endhp, a.dt, a.fa, a.lhp, a.fg, a.obs, a.idps, a.ew, a.er, a.ec, a.oc, a.err],
        [1, 0.4, null, null, 65, 35, 59, 0.51, 0.19, 0, 0.7, 0.48, 20, 0.16, 84, 42, 1, 1, 0.12, 0.31, 15]);
    assert.deepStrictEqual([b.swung, b.w, b.why, b.sw, b.hp, b.err], [0, 0.8, 'range', 1, null, null]);
    assert.deepStrictEqual([c.swung, c.reason, c.endhp, c.fa, c.lhp, c.obs, c.err], [1, 'missed', 4, null, null, null, null]);
    assert.deepStrictEqual([d.swung, d.lhp, d.obs, d.idps, d.ew, d.err], [1, 0, 0, 0, null, null]);
});
