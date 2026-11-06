'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'leave_ready.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lr-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const wave = (w, own, rule, sup) => `lane_ctl team=2 lane=3 kind=wave wave=${w} mode=safe rule=${rule} tgt=900 own=${own} mv=0 st=OUT need=0 intent=back lever=none sup=${sup}`;
const start = (job, pid) => `job job=${job} phase=start why=trigger pid=${pid} host=17`;

test('leave_ready: the lane at a support departure and one wave on', () => {
    const out = run([
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        // Stack at 215: read at 212 sat 100 past the target (ready), 30 s on 400 past (not); the reset wave read at 182 (R2)
        // and this support's ok pull at slot 197 come before it.
        line(182, wave(180, 1600, 'R2', 5)),
        line(200, 'pull_job pid=5 pos=5 lane=3 camp=1 slot=197 pk=full res=ok why=ok'),
        line(212, wave(210, 1000, 'R1', 5)),
        line(215, start('stack', 5)),
        line(242, wave(240, 1300, 'R3', '')),
        // Rune trip at 348: read at 332 600 past (not ready), at 392 100 past (ready); no pull before it.
        line(332, wave(330, 1500, 'R1', 5)),
        line(348, start('rune', 5)),
        line(362, wave(360, 1700, 'R3', '')),
        line(392, wave(390, 1000, 'R3', '')),
        // A core's camp trip and a departure with no read of its lane in the 30 s before: no rows.
        line(400, start('camp', 1)),
        line(500, start('stack', 5)),
    ]);
    const by = Object.fromEntries(out.map(r => [`${r.job}:${r.pulled}`, r]));
    assert.strictEqual(by['stack:1'].n, 1);
    assert.strictEqual(by['stack:1'].at_ready, 1);
    assert.strictEqual(by['stack:1'].after_ready, 0);
    assert.strictEqual(by['stack:1'].mean_at, 100);
    assert.strictEqual(by['stack:1'].mean_after, 400);
    assert.strictEqual(by['stack:1'].reset_share, 1);
    // The rune trip's next read 25 s or more after the leave is 392 (362 is 14 s on).
    assert.strictEqual(by['rune:0'].at_ready, 0);
    assert.strictEqual(by['rune:0'].after_ready, 1);
    assert.strictEqual(by['rune:0'].reset_share, 0);
    assert.strictEqual(by['all:all'].n, 2);
    assert.strictEqual(by['all:all'].both_ready, 0);
});
