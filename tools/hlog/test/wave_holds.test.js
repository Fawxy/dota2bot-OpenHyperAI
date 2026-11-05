'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'wave_holds.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-wh-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return Object.fromEntries(out.map(r => [r.br, r]));
}

// Team 2: pid 1 its bot-lane core, pid 5 the puller. Two diverted ok pulls whose wave was under our T1 by 30 s; one gets a hold.
const base = [
    line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
    line(195, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=200 res=ok why=ok dt=1'),
    line(200, 'lane_read team=2 lane=3 eq=0.2 fx=0 fy=-6000 tw=1'),
    line(230, 'lane_read team=2 lane=3 eq=-0.9 fx=0 fy=-6000 tw=1'),
    line(295, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=300 res=ok why=ok dt=1'),
    line(300, 'lane_read team=2 lane=3 eq=0.2 fx=0 fy=-6000 tw=1'),
    line(330, 'lane_read team=2 lane=3 eq=-0.9 fx=0 fy=-6000 tw=1'),
];

test('per branch: attempts, the mean last-hit share per attempt and the ends; coverage of pulls and tower moves by a hold starting within 30 s', () => {
    const out = run([...base,
        // started 210 (t - dur), inside the first pull's 30 s: covers it. 3 of 4 then 1 of 4: mean 0.5.
        line(240, 'wave_hold pid=1 lane=3 br=hold res=met why=pull n=4 lh=3 tw=0 sw=0 dur=30'),
        line(400, 'wave_hold pid=1 lane=3 br=hold res=tower why=other n=4 lh=1 tw=1 sw=0 dur=20'),
        line(420, 'wave_hold pid=1 lane=3 br=drag res=died why=aggro n=3 lh=0 tw=1 sw=1 dur=10'),
        // a tower move followed by a hold starting 20 s later (the drag above starts 410), one with none.
        line(390, 'aggro pid=1 role=core kind=tower result=ok'),
        line(500, 'aggro pid=1 role=core kind=tower result=ok'),
        line(505, 'aggro pid=1 role=core kind=tower result=stayed'),
    ]);
    assert.deepStrictEqual([out.hold.n, out.hold.lh_share, out.hold.met, out.hold.tower, out.hold.tw], [2, 0.5, 1, 1, 1]);
    assert.deepStrictEqual([out.drag.n, out.drag.died, out.drag.sw], [1, 1, 1]);
    assert.deepStrictEqual([out.cover_pull.n, out.cover_pull.missed], [2, 1]);
    assert.deepStrictEqual([out.cover_tower.n, out.cover_tower.missed], [2, 1]);
});
