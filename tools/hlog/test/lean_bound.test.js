'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lean_bound.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lean-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

const snap = (t, x, ld) => line(t, `snap pid=4 x=${x} y=0 alive=1 hp=100 mode=farm d=0.3 deaths=0 ln=bot s=0.3 ld=${ld} ol=0 ar=550 hit=0`);
const job = (t, kind, phase) => line(t, `job pid=4 job=${kind} phase=${phase} why=trigger host=19 hit=0`);

test('lean bound: corridor seconds end at the lane-path width or the spot\'s back limit, out-of-lane starts and open trips apart', () => {
    const lines = [line(0, 'bot pid=4 hero=h4 team=2 pos=5')];
    // Pull at 100: walks off the lane path, ld past 250 first at 104 (4 s), ends 112.
    lines.push(job(100, 'pull', 'start'), job(112, 'pull', 'end'));
    [100, 150, 200, 240, 300, 400, 500].forEach((ld, i) => lines.push(snap(100 + i, 0, ld)));
    // Stack at 200: walks along the lane path (ld stays 100), more than 1,000 from its start first at 203 (1,200; 202 is 800).
    lines.push(job(200, 'stack', 'start'), job(220, 'stack', 'end'));
    for (let i = 0; i <= 5; i++) lines.push(snap(200 + i, 400 * i, 100));
    // Stack at 300 from 600 off the lane path: not in lane, its trip time still counts.
    lines.push(job(300, 'stack', 'start'), job(310, 'stack', 'end'));
    for (let i = 0; i <= 3; i++) lines.push(snap(300 + i, 0, 600));
    // Rune at 400: stays in the corridor for the whole 45 s window, no end line.
    lines.push(job(400, 'rune', 'start'));
    for (let i = 0; i <= 46; i++) lines.push(snap(400 + i, 0, 100));
    // A pull before :from is left out.
    lines.push(job(50, 'pull', 'start'), job(52, 'pull', 'end'), snap(50, 0, 100), snap(51, 0, 400));
    const out = run(lines).map(r => [r.job, r.starts, r.in_lane, r.trip_s, r.corr_s, r.per_trip, r.ge2, r.open]);
    assert.deepStrictEqual(out, [
        ['pull', 1, 1, 12, 4, 4, 1, 0],
        ['rune', 1, 1, null, null, 0, 0, 1],
        ['stack', 2, 1, 15, 3, 1.5, 1, 0],
    ]);
});

test('lean bound: a wider corridor keeps a sideways walk in it longer', () => {
    const lines = [line(0, 'bot pid=4 hero=h4 team=2 pos=5'), job(100, 'pull', 'start'), job(110, 'pull', 'end')];
    [100, 200, 300, 400, 500].forEach((ld, i) => lines.push(snap(100 + i, 0, ld)));
    assert.deepStrictEqual(run(lines).map(r => r.corr_s), [2]);
    assert.deepStrictEqual(run(lines, { width: 450 }).map(r => r.corr_s), [4]);
});

test('lean bound: a job that ends before its hero leaves the corridor counts only to its end', () => {
    const lines = [line(0, 'bot pid=4 hero=h4 team=2 pos=5'), job(100, 'pull', 'start'), job(102, 'pull', 'end')];
    [100, 100, 100, 100, 400].forEach((ld, i) => lines.push(snap(100 + i, 0, ld)));
    assert.deepStrictEqual(run(lines).map(r => r.corr_s), [2]);
});
