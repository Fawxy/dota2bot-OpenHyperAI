'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { hits } = require('../threat_grade');
const { run } = require('../missing_grade');

function store(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-tg-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}
const snap = (t, pid, x, y, hp = 100) => `[HEV] t=${t.toFixed(1)} ev=snap pid=${pid} x=${x} y=${y} alive=1 hp=${hp} mp=50 lvl=1 lh=0 dn=0 mode=laning d=0.3 act=2 gold=600`;

// Every hero of both teams parked far away, except the ones the test places.
function world(place, seconds) {
    const out = [];
    for (let t = 0; t <= seconds; t++) for (let pid = 0; pid < 10; pid++) {
        const p = place(t, pid);
        out.push(snap(t, pid, p.x, p.y, p.hp));
    }
    return out;
}

test('hits: an attacker 700 away two seconds before is in reach; one that blinked in from 3000 is a miss', () => {
    const s = store(world((t, pid) => {
        const far = { x: -7000 + pid * 100, y: 7000 };
        if (pid === 0) return { x: 0, y: 0, hp: t >= 10 ? 70 : 100 };
        if (pid === 5) return { x: t >= 9.5 ? 300 : 700, y: 0 };
        return far;
    }, 12));
    // The first hit at t=10 comes from pid 5, who was at 700 at t=8.
    const r = hits(s, [1]);
    assert.equal(r.hits, 1);
    assert.equal(r.heroHits, 1);
    assert.equal(r.attackers, 1);
    assert.equal(r.inReach, 1);
    assert.equal(r.misses.length, 0);
    s.db.close();
});

test('hits: a blink from beyond speed x 2 s plus range is listed as a miss', () => {
    const s = store(world((t, pid) => {
        if (pid === 0) return { x: 0, y: 0, hp: t >= 10 ? 70 : 100 };
        if (pid === 5) return { x: t >= 9 ? 300 : 3000, y: 0 };
        return { x: -7000 + pid * 100, y: 7000 };
    }, 12));
    const r = hits(s, [1]);
    assert.equal(r.inReach, 0);
    assert.equal(r.misses.length, 1);
    s.db.close();
});

test('missing_grade: two heroes unseen since t=15 are both counted by the live rule, only the one that walks to the camp is true', () => {
    const lines = world((t, pid) => {
        if (pid === 2) return { x: -6000, y: 3000 };
        if (pid === 7) return t < 15 ? { x: -5000, y: 3500 } : { x: -4300, y: 3900 };
        if (pid === 8) return t < 15 ? { x: -5000, y: 3500 } : { x: -1000, y: -3000 };
        return { x: -7000 + pid * 100, y: 7000 };
    }, 50);
    lines.push('[HEV] t=30.0 ev=lane_ctl team=2 lane=1 kind=wave wave=30 core=2 cmiss=2 closs=10 cwhy=missing');
    const s = store(lines);
    const o = run(s).rules.live;
    assert.equal(o.refused, 1);
    assert.equal(o.perHero, 2);
    assert.equal(o.perHeroTrue, 1);
    s.db.close();
});

test('missing_grade support-pull: a hero unseen after 4:00 by the walk holds the pull at weight 0.5; the hold is true when it walks to the camp', () => {
    const camp = { x: 3000, y: -5000 };
    const lines = world((t, pid) => {
        if (pid === 4) return { x: 1500, y: -6000 };
        // Seen by pid 4 until 250, then unseen 1500 from the walk; walks onto the camp by 265.
        if (pid === 7) return t < 250 ? { x: 1500, y: -4500 } : t < 262 ? { x: 2600, y: -3200 } : camp;
        return { x: -7000 + pid * 100, y: 7000 };
    }, 280);
    lines.push(`[HEV] t=-5.0 ev=camp type=small idx=1 team=2 x=${camp.x} y=${camp.y} x0=0 y0=0 x1=0 y1=0`);
    lines.push('[HEV] t=275.0 ev=pull_job pid=4 pos=5 lane=3 camp=1 slot=270 res=ok left=258 hit=1 died=0');
    const s = store(lines);
    const r = run(s, { rows: 'support-pull' });
    assert.equal(r.rows, 1);
    assert.deepEqual(r.outcome.held, { n: 1, hit: 1, died: 0, after: 0, show: 1 });
    assert.equal(r.outcome.allowed.n, 0);
    s.db.close();
});

test('missing_grade support-pull: one unseen hero before 4:00 weighs 0.2 and the pull is allowed', () => {
    const camp = { x: 3000, y: -5000 };
    const lines = world((t, pid) => {
        if (pid === 4) return { x: 1500, y: -6000 };
        if (pid === 7) return t < 150 ? { x: 1500, y: -4500 } : { x: 2600, y: -3200 };
        return { x: -7000 + pid * 100, y: 7000 };
    }, 180);
    lines.push(`[HEV] t=-5.0 ev=camp type=small idx=1 team=2 x=${camp.x} y=${camp.y} x0=0 y0=0 x1=0 y1=0`);
    lines.push('[HEV] t=175.0 ev=pull_job pid=4 pos=5 lane=3 camp=1 slot=170 res=ok left=160 hit=0 died=0');
    const r = run(store(lines), { rows: 'support-pull' });
    assert.equal(r.outcome.held.n, 0);
    assert.equal(r.outcome.allowed.n, 1);
});

test('missing_grade stack: the hit comes from the job end line, and a death within 15 s of the line counts as after', () => {
    const camp = { x: 3000, y: -5000 };
    const lines = world((t, pid) => {
        if (pid === 4) return { x: 1500, y: -6000 };
        if (pid === 7) return t < 250 ? { x: 1500, y: -4500 } : { x: 2600, y: -3200 };
        return { x: -7000 + pid * 100, y: 7000 };
    }, 300).filter(l => !(/ pid=4 /.test(l) && Number(l.match(/t=(\S+)/)[1]) > 268 && Number(l.match(/t=(\S+)/)[1]) < 290));
    lines.push(`[HEV] t=-5.0 ev=camp type=small idx=1 team=2 x=${camp.x} y=${camp.y} x0=0 y0=0 x1=0 y1=0`);
    lines.push('[HEV] t=262.0 ev=stack res=stacked why=ok pid=4 camp=1 start=258 hpa=100 hpe=100 death=0');
    lines.push('[HEV] t=263.0 ev=job job=stack phase=end why=ok pid=4 host=17 hit=1');
    const r = run(store(lines), { rows: 'stack' });
    assert.deepEqual(r.outcome.held, { n: 1, hit: 1, died: 0, after: 1, show: 0 });
});
