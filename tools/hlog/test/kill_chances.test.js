'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { tally } = require('../kill_chances');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'kill_chances.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-kc-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, { until: 720, pos_lo: 1, pos_hi: 5 });
    s.db.close();
    return out;
}

const snap = (t, pid, { x, y = -6000, hp = 80, mode = 'laning', tgt = '', deaths = 0 }) =>
    line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${hp} mode=${mode} d=0.3 deaths=${deaths} ln=bot ol=0 ar=500 hit=0${tgt ? ` tid=${tgt}` : ''}`);

test('kill chances: runs of low seconds with a hunter in 1,000, attackers in 8 s, a death in 12 s, hunters by position', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=2 hero=h2 team=2 pos=4'), line(0, 'bot pid=6 hero=h6 team=3 pos=3')];
    // 100-108: pid 6 (Dire) at 30% then 10%, 0% at 109, dead (fountain, deaths=1) at 140. Our core pid 1 500 away attacks it
    // (mode attack 101-106, tid at 103-104); our support pid 2, 1,500 away (no hunter), hits it at 105: two attackers, one hunter.
    for (let t = 100; t <= 109; t++) {
        lines.push(snap(t, 6, { x: 1000, hp: t === 109 ? 0 : t >= 106 ? 10 : 30 }));
        lines.push(snap(t, 1, { x: 1500, mode: t >= 101 && t <= 106 ? 'attack' : 'laning', tgt: t === 103 || t === 104 ? 'h6' : '' }));
        lines.push(snap(t, 2, { x: 2500, tgt: t === 105 ? 'h6' : '' }));
    }
    lines.push(snap(140, 6, { x: 6928, y: 6372, hp: 100, deaths: 1 }));
    // 300, 310 and 330: our pid 1 low with pid 6 (healthy) 800 away and idle; 310 is 10 s after 300 (one chance), 330 is 20 s
    // after 310 (a new one). 400: both low, no hunter. 715: past 11:48, not counted.
    for (const t of [300, 310, 330, 400, 715]) {
        lines.push(snap(t, 1, { x: 1000, hp: 30 }));
        lines.push(snap(t, 6, { x: 1800, y: -6000, hp: t === 400 ? 35 : 90, deaths: 1 }));
        lines.push(snap(t, 2, { x: -3000 }));
    }
    const out = run(lines);
    assert.deepStrictEqual(out.map((r) => [r.pid, r.team, r.t, r.attackers, r.died, r.nh, r.hpid, r.hpos, r.dist, r.hatk, r.hmode]), [
        [6, 3, 100, 2, 1, 1, 1, 1, 500, 1, 'attack'],
        [1, 2, 300, 0, 0, 1, 6, 3, 800, 0, 'laning'],
        [1, 2, 330, 0, 0, 1, 6, 3, 800, 0, 'laning'],
    ]);
});

test('kill chances tally: a chance counted once over its hunters, groups by hunter position', () => {
    const rs = [
        { label: 'a', pid: 6, t: 100, attackers: 2, died: 1, hpos: 1, hatk: 1, hmode: 'attack' },
        { label: 'a', pid: 6, t: 100, attackers: 2, died: 1, hpos: 4, hatk: 0, hmode: 'laning' },
        { label: 'a', pid: 7, t: 200, attackers: 0, died: 0, hpos: 3, hatk: 0, hmode: 'laning' },
    ];
    const t = tally(rs, 2);
    assert.strictEqual(t.chances, 1);
    assert.strictEqual(t.attacked, 0.5);
    assert.strictEqual(t.two, 0.5);
    assert.strictEqual(t.died, 0.5);
    assert.deepStrictEqual(t.groups.cores, { n: 1, atk: 0.5, modes: [['laning', 0.5]] });
    assert.deepStrictEqual(t.groups.supports, { n: 0.5, atk: 0, modes: [['laning', 1]] });
});
