'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'support_idle.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-si-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const snap = (pid, mode, ph) => `snap pid=${pid} x=0 y=0 alive=1 hp=100 lh=0 dn=0 kills=0 deaths=0 mode=${mode} lf="ph=${ph} sc=0.1 aw=500"`;

test('support_idle: hold share of a support\'s laning time, 1:00-10:00', () => {
    const lines = [
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=6 hero=h6 team=2 pos=4'),
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    ];
    // pid 5: 4 laning snaps (3 hold, 1 deny) and 4 on a job; one hold before 1:00 and one after 10:00 do not count.
    [70, 71, 72].forEach(t => lines.push(line(t, snap(5, 'laning', 'hold'))));
    lines.push(line(73, snap(5, 'laning', 'deny')));
    [80, 81, 82, 83].forEach(t => lines.push(line(t, snap(5, 'side_shop', 'walk'))));
    lines.push(line(50, snap(5, 'laning', 'hold')), line(610, snap(5, 'laning', 'hold')));
    // pid 6: 2 laning snaps, 1 hold. A core's snaps do not count.
    lines.push(line(90, snap(6, 'laning', 'hold')), line(91, snap(6, 'laning', 'lasthit')));
    lines.push(line(90, snap(1, 'laning', 'hold')));
    const by = Object.fromEntries(run(lines).map(r => [String(r.pos), r]));
    assert.strictEqual(by['5'].snaps, 4);
    assert.strictEqual(by['5'].hold_share, 0.75);
    assert.strictEqual(by['5'].laning_share, 0.5);
    assert.strictEqual(by['4'].hold_share, 0.5);
    assert.strictEqual(by.all.n, 2);
    assert.strictEqual(by.all.hold_share, 0.67);
    assert.strictEqual(by['1'], undefined);
});
