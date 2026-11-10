'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'linger_windows.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lw-')), 'a.log');
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
const pos = (t, o) => line(t, `lane_pos pid=0 d=10 owned=1 running=1 mode=1 spot=front why=${o.why ?? 'pref'} rb=${o.rb ?? 0.1} rm=${o.rm ?? 0} ${o.mp ? `mp=${o.mp} ` : ''}op=${o.op ?? 'none'} rp=${o.rp ?? 'none'}`);

test('linger windows: hit-flag HP loss, farm, read-only and old-limit-only pushes, the chaser unseen, an episode end, one row per window', () => {
    const out = run([
        line(98, 'drill ph=linger_go name=retreat-linger pid=9 tpid=0 rep=1 thp=0.4 d=300 rend=105'),
        line(100, 'drill ph=linger name=retreat-linger pid=9 tpid=0 rep=1 thp=0.4 d=1100'),
        line(112, 'drill ph=linger_end name=retreat-linger pid=9 tpid=0 rep=1 res=contact secs=12 dmin=240 dmax=1150 dend=240 uns=2.5 clamp=0'),
        // The cast's HP falls 40 -> 36 -> 30 across the window; only the second second was hit (the first drop is not counted).
        snap(100, 0, { hp: 40, lh: 5 }), snap(101, 0, { hp: 36, lh: 5 }), snap(102, 0, { hp: 30, hit: 1, lh: 5 }), snap(110, 0, { hp: 30, lh: 6, dn: 1 }),
        // Outside the window: not counted.
        snap(113, 0, { hp: 10, hit: 1 }), snap(95, 0, { hp: 50, hit: 1 }),
        // The chaser's own snaps are not the cast's.
        snap(101, 9, { hp: 100, hit: 1 }),
        line(98, 'retreat ph=start pid=0 kind=ours ep=1 why=threat hp=0.4 thr=0.62 band=pressured reach=1 burst=0.2 tower=0 budget=0.5 purp=free anchor=tower cost=1 alt=3 dist=2400'),
        line(104, 'retreat ph=end pid=0 kind=ours ep=1 why=threat anchor=tower res=safe secs=6 hpl=0.1 twr=0 wave=1 dmgh=0.05'),
        pos(101, { rb: 0.2, rm: 0.3, mp: '9,8', rp: 'burst', op: 'none' }),
        pos(102, { rb: 0.5, rm: 0.1, mp: '8', rp: 'none', op: 'hero', why: 'xp' }),
        pos(103, { rb: 0.1, rm: 0, rp: 'none', op: 'none' }),
        pos(120, { rb: 0.9, rm: 0.9, mp: '9', rp: 'burst' }),
        // A second window with no end line (the game stopped): it runs 20 s, and nothing leaks across games or windows.
        line(200, 'drill ph=linger_go name=retreat-linger pid=9 tpid=0 rep=3 thp=0.3 d=300 rend=300'),
        snap(201, 0, { hp: 30 }), snap(210, 0, { hp: 25, hit: 1 }),
    ], { like: null });
    assert.strictEqual(out.length, 2);
    const [a, b] = out;
    assert.deepStrictEqual([a.rep, a.t0, a.thp, a.dgo, a.res, a.secs_to_contact, a.dmin, a.clamp], [1, 100, 0.4, 300, 'contact', 12, 240, 0]);
    assert.strictEqual(a.hpl, 6);
    assert.deepStrictEqual([a.lh, a.dn], [1, 1]);
    assert.deepStrictEqual([a.ep, a.epend], [1, 1]);
    assert.strictEqual(a.rb, 0.5);
    assert.strictEqual(a.rm, 0.3);
    assert.strictEqual(a.unseen, 1);
    assert.strictEqual(a.xp, 1);
    assert.strictEqual(a.rpush, 1);
    assert.strictEqual(a.opush, 1);
    assert.deepStrictEqual([a.tgo, a.dmax, a.dend, a.uns, a.ctl], [98, 1150, 240, 2.5, 7]);
    // No stand-off reached: no t0; the window is graded from the trigger and runs 20 s.
    assert.strictEqual(b.t0, null);
    assert.strictEqual(b.res, null);
    assert.strictEqual(b.hpl, 5);
});
