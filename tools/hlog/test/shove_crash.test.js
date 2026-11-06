'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'shove_crash.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-sc-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const lr = (t, team, lane, eq) => line(t, `lane_read team=${team} lane=${lane} eq=${eq}`);

test('shove crash: 30 s cycles 1:00-10:00 per team and lane, crashed when eq reaches 0.75', () => {
    const out = run([
        line(0, 'bot pid=0 hero=h0 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=3 pos=1'),
        // Before 1:00 is not counted.
        lr(30, 2, 3, 0.9),
        // Cycle 2 (60-89): one reading reaches 0.8: crashed.
        lr(61, 2, 3, 0.2), lr(70, 2, 3, 0.8),
        // Cycle 3 (90-119): 0.7 at most: not crashed.
        lr(95, 2, 3, 0.7),
        // Cycle 4: exactly 0.75: crashed. A null eq reading (-1 is a value) is kept.
        lr(125, 2, 3, 0.75),
        // At 10:00 and later is not counted.
        lr(600, 2, 3, 0.9),
        // Another lane and team.
        lr(65, 2, 1, 0.1),
        lr(65, 3, 3, 0.9),
        line(80, 'idle_swing pid=0 kind=shove mode=shove result=ok reason=ok ranged=0 walk=0 hp=100 hf=0.2'),
        line(82, 'idle_swing pid=0 kind=shove mode=shove result=ok reason=ok ranged=0 walk=0 hp=50 hf=0.1'),
        line(84, 'idle_swing pid=0 kind=predeny mode=safe result=ok reason=ok ranged=0 walk=0 hp=50 hf=0.1'),
    ]);
    const row = (team, lane) => out.find(r => r.team === team && r.lane === lane);
    const r = row(2, 3);
    assert.deepStrictEqual([r.cycles, r.crashed, r.share, r.shoves], [3, 2, 0.67, 2]);
    assert.deepStrictEqual([row(2, 1).cycles, row(2, 1).crashed, row(2, 1).shoves], [1, 0, 2]);
    assert.deepStrictEqual([row(3, 3).crashed, row(3, 3).shoves], [1, 0]);
});
