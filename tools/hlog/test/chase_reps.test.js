'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'chase_reps.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cr-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

const snap = (t, pid, o = {}) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=${o.hp ?? 100} mp=50 lvl=1 lh=${o.lh ?? 0} dn=${o.dn ?? 0} kills=0 deaths=0 mode=laning d=0.3 act=2 gold=600 hit=${o.hit ?? 0}`);
const pos = (t, o) => line(t, `lane_pos pid=0 d=10 owned=1 running=1 mode=1 spot=front why=pref rp=${o.rp ?? 'none'} op=none${o.re !== undefined ? ` re=${o.re}` : ''}`);

test('chase reps: lowest HP, hit-flag loss before the trigger, farm, full-HP read pushes and engaged frames, per odd rep', () => {
    const out = run([
        line(0.5, 'drill ph=role name=retreat-linger pid=0 team=2 pos=1 role=cast'),
        line(0.5, 'drill ph=role name=retreat-linger pid=9 team=3 pos=3 role=chaser'),
        line(60, 'drill ph=rep name=retreat-linger team=2 rep=1 input=on start=60'),
        line(120, 'drill ph=rep name=retreat-linger team=2 rep=2 input=off start=120'),
        line(180, 'drill ph=rep name=retreat-linger team=2 rep=3 input=on start=180'),
        // Rep 1: 100 -> 90 (hit) -> 70 (hit) -> trigger at 80 -> 40 (hit, after the trigger: not counted); lh 2, dn 1.
        snap(61, 0, { hp: 100, lh: 1 }), snap(62, 0, { hp: 90, hit: 1, lh: 1 }), snap(64, 0, { hp: 70, hit: 1, lh: 2, dn: 1 }),
        snap(81, 0, { hp: 40, hit: 1, lh: 3, dn: 1 }),
        line(80, 'drill ph=linger_go name=retreat-linger pid=9 tpid=0 rep=1 thp=0.45 d=300 rend=120'),
        // Frames: one at full HP the read pushed, one at 70% pushed (not full HP), two engaged.
        pos(61.5, { rp: 'burst', re: 1 }), pos(64.5, { rp: 'burst', re: 1 }), pos(62.5, { rp: 'none', re: 0 }),
        // The control rep (even) is not a row. Rep 3: no trigger, HP never under 80.
        snap(181, 0, { hp: 100, lh: 3 }), snap(190, 0, { hp: 85, hit: 1, lh: 4, dn: 1 }), snap(200, 0, { hp: 80, hit: 1, lh: 5, dn: 1 }),
        snap(70, 9, { hp: 5 }),
    ], { like: null });
    assert.strictEqual(out.length, 2);
    const [a, b] = out;
    assert.deepStrictEqual([a.rep, a.low, a.trig, a.tgo, a.hpl_pre, a.hit_secs, a.lh, a.dn], [1, 40, 1, 80, 30, 2, 2, 1]);
    assert.deepStrictEqual([a.rpush, a.re], [1, 2]);
    assert.deepStrictEqual([b.rep, b.low, b.trig, b.hpl_pre, b.hit_secs, b.lh, b.dn, b.rpush, b.re], [3, 80, 0, 20, 10, 2, 1, 0, 0]);
});
