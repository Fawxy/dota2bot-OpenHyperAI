'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const aggro = (t, o) => line(t, `aggro pid=${o.pid ?? 1} role=${o.role ?? 'core'} kind=${o.kind} result=${o.result} tgt=6 near=3`
    + ` drawn=${o.drawn ?? 0} onr=${o.onr ?? 0} dhp=${o.dhp ?? 0} hp=0.9 dur=2`);
const own = (t, kind, by) => line(t, `own_creep_death team=2 kind=${kind} x=0 y=0 hp=0 by=${by}`);

test('lane aggro: per kind and role, results, draws and HP; ranged-creep deny coverage per game; nothing after :until', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=4 hero=h4 team=2 pos=4')];
    lines.push(aggro(100, { kind: 'feed', result: 'denied', drawn: 3, onr: 2, dhp: 20 }));
    lines.push(aggro(130, { kind: 'feed', result: 'lost', drawn: 1, onr: 0, dhp: 40 }));
    lines.push(aggro(160, { kind: 'feed', result: 'no_draw' }));
    lines.push(aggro(170, { kind: 'drag', result: 'ok', drawn: 2, dhp: 10 }));
    lines.push(aggro(180, { kind: 'feed', result: 'denied', role: 'support', pid: 4, drawn: 2, onr: 1 }));
    lines.push(aggro(650, { kind: 'feed', result: 'denied', drawn: 2, onr: 1 }));
    // Coverage: three ranged deaths before 600 (one ours), a melee deny and a late ranged deny that do not count.
    lines.push(own(101, 'ranged', 1), own(131, 'ranged', 'none'), own(200, 'ranged', 'none'), own(210, 'melee', 1), own(640, 'ranged', 1));
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lag-')), 'a.log');
    const at = l => Number(l.match(/t=([\d.]+)/)[1]);
    fs.writeFileSync(f, lines.sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lane_aggro.sql'), 'utf8');
    const rows = s.query(sql, {}).map(r => [r.kind, r.role, r.tries, r.denied, r.ok, r.lost, r.no_draw, r.drew, r.onr_any, r.dhp, r.rn, r.rd]);
    assert.deepStrictEqual(rows, [
        ['drag', 'core', 1, 0, 1, 0, 0, 1, 0, 10, 3, 1],
        ['feed', 'core', 3, 1, 0, 1, 1, 2, 1, 20, 3, 1],
        ['feed', 'support', 1, 1, 0, 0, 0, 1, 1, 0, 3, 1],
    ]);
    s.db.close();
});
