'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lane_ctl.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lc-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const wave = (t, w, extra) => `lane_ctl team=2 lane=3 kind=wave wave=${w} mode=safe rule=R1 tgt=900 own=1500 mv=200 st=OUT need=800 ${extra}`;
const chk = (t, w, own) => `lane_ctl team=2 lane=3 kind=chk wave=${w} own=${own} mv=0 st=HOLD`;

test('lane_ctl: decisions joined to their check, the pull term only on a pulled wave', () => {
    const out = run([
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        // Wave 90: pull chosen and pulled (slot 106): the controller predicts m45 + pe = 1600 - 700 = 900; it ended at 1000.
        line(92, wave(92, 90, 'm45=1600 p45=433 pe=-700 n45=700 intent=back lever=pull who=5 left=0 rej=')),
        line(110, 'pull_job pid=5 pos=5 lane=3 camp=1 slot=106 pk=full res=ok why=ok'),
        line(137, chk(137, 90, 1000)),
        // Wave 120: no pull: the controller's prediction is the plain forecast, 1000 against 1200.
        line(122, wave(122, 120, 'm45=1000 n45=100 intent=hold lever=none who= left=100 rej=')),
        line(167, chk(167, 120, 1200)),
        // Wave 150: no check line: left out.
        line(152, wave(152, 150, 'm45=1000 n45=100 intent=hold lever=none who= left=100 rej=')),
    ]);
    const all = Object.fromEntries(out.filter(r => r.intent === 'all').map(r => [r.pulled, r]));
    assert.strictEqual(all[1].n, 1);
    assert.strictEqual(all[1].e_plain, 600);
    assert.strictEqual(all[1].e_ctl, 100);
    assert.strictEqual(all[1].e_none, 500);
    assert.strictEqual(all[1].in_band, 1);
    assert.strictEqual(all[0].n, 1);
    assert.strictEqual(all[0].e_ctl, 200);
    assert.strictEqual(all[0].e_plain, 200);
    const hold = out.find(r => r.pulled === 0 && r.intent === 'hold');
    assert.strictEqual(hold.lever, 'none');
    // Slice 2b: the pull at slot 106 has no div field, so the wave is pulled but not diverted. The back wave read own 1500
    // (600 past the target 900) and checked at 1000 (100 past): nearer. Hold waves are not scored for it.
    assert.strictEqual(all[1].div, 0);
    assert.strictEqual(all[1].nearer, 1);
    assert.strictEqual(hold.nearer, null);
});
