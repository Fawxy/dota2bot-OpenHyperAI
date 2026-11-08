'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'contest.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cw-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return Object.fromEntries(out.map(r => [r.pid, r]));
}

const lh = (pid, result, reason, extra, msg) =>
    `lh pid=${pid} kind=lasthit result=${result} reason=${reason} ranged=0 eta=1.5 walk=1.4 dies=3.2${extra} msg="${msg}"`;

test('contest: walk-ins split by how they ended, refusals by place and reason, plain attempts ignored', () => {
    const out = run([
        line(0, 'bot pid=1 hero=sven team=2 pos=1'),
        line(0, 'bot pid=5 hero=axe team=3 pos=3'),
        line(100, lh(1, 'ok', 'ok', ' cw=1 cc=4 cn=1 dh=2', 'w=1.5 hp=60')),
        line(110, lh(1, 'fail', 'interrupted', ' cw=1 cc=6 cn=1 dh=0', 'w=0.3 why=range sw=1')),
        line(120, lh(1, 'fail', 'interrupted', ' cw=1 cc=8 cn=1 dh=1', 'w=0.5 why=range sw=0')),
        line(130, lh(1, 'fail', 'interrupted', ' cw=1 cc=2 cn=1 dh=-3', 'w=1.4 why=range')),
        line(140, lh(1, 'fail', 'denied', ' cw=1 cc=0 cn=0 dh=0', 'w=1.6')),
        // A plain attempt (no cw) is not a walk-in.
        line(150, lh(1, 'ok', 'ok', '', 'w=0.4')),
        line(160, 'contest_skip pid=1 at=pick why=cost cc=12 n=1 ex=2 walk=2 dies=4 hf=1'),
        line(161, 'contest_skip pid=1 at=walk why=two cc=9 n=2 ex=2 walk=1 dies=3 hf=0.9'),
        // Pid 5 only refused: a row with no walk-ins.
        line(170, 'contest_skip pid=5 at=pick why=tower cc=3 n=1 ex=1 walk=1.5 dies=4 hf=1'),
        // After :until.
        line(700, lh(1, 'ok', 'ok', ' cw=1 cc=4 cn=1 dh=50', 'w=1.5')),
    ]);
    const s = out[1];
    assert.deepStrictEqual([s.hero, s.walkins, s.landed, s.retarget, s.released, s.leash, s.denied, s.taken, s.other],
        ['sven', 5, 1, 1, 1, 1, 1, 0, 0]);
    assert.deepStrictEqual([s.rate, s.rate_nosw, s.dh_mean, s.dh_max, s.cc_mean], [0.2, 0.25, 0, 2, 4]);
    assert.deepStrictEqual([s.pick_cost, s.walk_two, s.pick_two], [1, 1, 0]);
    assert.deepStrictEqual([out[5].walkins, out[5].rate, out[5].pick_tower], [0, null, 1]);
});
