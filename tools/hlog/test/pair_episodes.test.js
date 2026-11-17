'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { tally } = require('../pair_episodes');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pair_episodes.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pe-')), 'a.log');
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

test('pair episodes: fights by target and gap, the partner, its first hit, last hits, retreats, kills and deaths', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=2 hero=h2 team=2 pos=4'),
        line(0, 'bot pid=3 hero=h3 team=2 pos=5'), line(0, 'bot pid=6 hero=h6 team=3 pos=3'), line(0, 'bot pid=7 hero=h7 team=3 pos=4')];
    // 100-110: pid 1 hits pid 6 at 100-104, pid 2 (600 away) hits it at 103, 104 and 106 and pid 7 at 105: one fight 100-106,
    // partner gap 3, split. pid 3 is 3,000 away (not in reach). pid 6 falls to 20% and dies (fountain, deaths=1, at 140).
    for (let t = 100; t <= 110; t++) {
        lines.push(snap(t, 6, { x: 1000, hp: t >= 109 ? 0 : t >= 104 ? 20 : 60 }));
        lines.push(snap(t, 7, { x: 1100, hp: 90 }));
        lines.push(snap(t, 1, { x: 1400, tgt: t <= 104 ? 'h6' : '' }));
        lines.push(snap(t, 2, { x: 1600, tgt: t === 105 ? 'h7' : t >= 103 && t <= 106 ? 'h6' : '' }));
        lines.push(snap(t, 3, { x: 4000 }));
    }
    lines.push(snap(140, 6, { x: 6928, y: 6372, hp: 100, deaths: 1 }));
    // 300-320: pid 1 hits pid 7 at 300 and at 302; pid 3 near (500) never hits; pid 1 retreats from 304, pid 3 from 306.
    // 312: pid 1 hits pid 7 again, more than 5 s later: a second fight, partner pid 3 again. 400: pid 1 hits pid 7 with nobody near.
    for (let t = 300; t <= 320; t++) {
        lines.push(snap(t, 7, { x: 1000, hp: 70 }));
        lines.push(snap(t, 6, { x: 5000, hp: 100, deaths: 1 }));
        lines.push(snap(t, 1, { x: 1400, mode: t >= 304 && t < 312 ? 'retreat' : 'laning', tgt: t === 300 || t === 302 || t === 312 ? 'h7' : '' }));
        lines.push(snap(t, 3, { x: 1500, mode: t >= 306 && t < 312 ? 'retreat' : 'laning' }));
        lines.push(snap(t, 2, { x: -3000 }));
    }
    lines.push(snap(400, 7, { x: 1000 }));
    lines.push(snap(400, 1, { x: 1400, tgt: 'h7' }));
    lines.push(snap(400, 3, { x: 4000 }));
    const out = run(lines);
    assert.deepStrictEqual(out.map((r) => [r.team, r.tpid, r.t0, r.t1, r.p1, r.p2, r.gap2, r.members, r.split, r.last1, r.last2,
        r.ret1, r.ret2, r.minhp, r.en, r.al, r.tdied, r.d1, r.d2]), [
        [2, 6, 100, 106, 1, 2, 3, 2, 1, 104, 106, null, null, 20, 2, 2, 1, 0, 0],
        // pid 2's one hit on pid 7 at 105 is a pair fight of its own (pid 1 within 1,200 of pid 7)
        [2, 7, 105, 105, 2, 1, null, 1, 0, 105, null, null, null, 90, 2, 2, 0, 0, 0],
        [2, 7, 300, 302, 1, 3, null, 1, 0, 302, null, 304, 306, 70, 1, 2, 0, 0, 0],
        [2, 7, 312, 312, 1, 3, null, 1, 0, 312, null, null, null, 70, 1, 2, 0, 0, 0],
    ]);
});

test('pair episodes tally: partner share, kills by both and by one, left together within 3 s', () => {
    const r = (o) => ({ gap2: null, split: 0, tdied: 0, minhp: 80, last1: 10, last2: null, ret1: null, ret2: null, d1: 0, d2: 0, en: 1, al: 2, ...o });
    const rs = [
        r({ gap2: 2, tdied: 1, minhp: 30, last2: 12, ret1: 20, ret2: 22 }),
        r({ gap2: 4, split: 1, last2: 13, en: 2, d2: 1 }),
        r({ ret1: 5, ret2: 15 }),
        r({ tdied: 1 }),
    ];
    const t = tally(rs, 2);
    assert.strictEqual(t.fights, 2);
    assert.deepStrictEqual(t.partner, { v: 0.5, n: 4 });
    assert.strictEqual(t.gap, 3);
    assert.deepStrictEqual(t.oneTarget, { v: 0.5, n: 2 });
    assert.deepStrictEqual(t.bothKilled, { v: 0.5, n: 2 });
    assert.deepStrictEqual(t.lowKilled, { v: 1, n: 1 });
    assert.deepStrictEqual(t.oneKilled, { v: 0.5, n: 2 });
    assert.strictEqual(t.stopGap, 3);
    assert.deepStrictEqual(t.together, { v: 0.5, n: 2 });
    assert.deepStrictEqual(t.diedEven, { v: 1, n: 1 });
});
