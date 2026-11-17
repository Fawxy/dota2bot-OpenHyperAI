'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { reps, summary } = require('../pair_rig');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const N = 'pair-kill';

function store(lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pr-'));
    const f = path.join(dir, 'drill_pair-kill_t.log');
    const at = (l) => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}

const snap = (t, pid, { hp = 80, mode = 'laning', tgt = '', deaths = 0, alive = 1 } = {}) =>
    line(t, `snap pid=${pid} x=0 y=0 alive=${alive} hp=${hp} mode=${mode} lh=0 dn=0 d=0.3 deaths=${deaths} hit=0${tgt ? ` tid=${tgt}` : ''}`);
const ready = (t, pid, rep, v) => line(t, `drill ph=ready name=${N} pid=${pid} rep=${rep} var=${v} ok=1`);

test('pair_rig: first hits and their gap, the kill, stops together, and the control apart', () => {
    const l = [
        line(0, 'bot pid=0 hero=sven team=2 pos=1'), line(0, 'bot pid=4 hero=wd team=2 pos=5'),
        line(0, 'bot pid=8 hero=lich team=3 pos=4'), line(0, 'bot pid=7 hero=bb team=3 pos=3'),
        line(0.5, `drill ph=role name=${N} pid=0 team=2 pos=1 role=cast`), line(0.5, `drill ph=role name=${N} pid=4 team=2 pos=5 role=cast`),
        line(1, `drill ph=rep name=${N} team=2 rep=1 input=on start=0`), line(120, `drill ph=rep name=${N} team=2 rep=2 input=on start=120`),
        line(240, `drill ph=rep name=${N} team=2 rep=3 input=on start=240`), line(360, `drill ph=rep name=${N} team=2 rep=4 input=on start=360`),
        // Rep 1 (low): ready at 50 and 51; Sven hits from 52, WD from 53; the Lich dies at 56.
        ready(50, 0, 1, 'low'), ready(51, 4, 1, 'low'),
        // Rep 2 (flee): both ready at 170; Sven hits 171-178, WD only 176-177, WD retreats at 179, Sven never: apart.
        ready(170, 0, 2, 'flee'), ready(170, 4, 2, 'flee'),
        // Rep 3 (outnum, control): ready, nobody hits.
        ready(290, 0, 3, 'outnum'), ready(290, 4, 3, 'outnum'),
    ];
    for (let t = 50; t <= 119; t++) {
        l.push(snap(t, 0, { tgt: t >= 52 && t <= 56 ? 'h8' : '' }));
        l.push(snap(t, 4, { tgt: t >= 53 && t <= 56 ? 'h8' : '' }));
        l.push(snap(t, 8, { hp: t >= 56 ? 0 : 30, alive: t >= 56 ? 0 : 1, deaths: t >= 56 ? 1 : 0 }));
    }
    for (let t = 170; t <= 239; t++) {
        l.push(snap(t, 0, { tgt: t >= 171 && t <= 178 ? 'h8' : '' }));
        l.push(snap(t, 4, { tgt: t >= 176 && t <= 177 ? 'h8' : '', mode: t >= 179 ? 'retreat' : 'laning' }));
        l.push(snap(t, 8, { hp: 25, deaths: 1 }));
    }
    for (let t = 290; t <= 359; t++) {
        l.push(snap(t, 0));
        l.push(snap(t, 4));
        l.push(snap(t, 8, { hp: 30, deaths: 1 }));
    }
    // Rep 4 never reached ready for WD: dropped.
    l.push(ready(400, 0, 4, 'low'), snap(400, 0), snap(401, 4), snap(410, 0));
    const s = store(l);
    const rs = reps(s, 'drill_pair-kill');
    s.db.close();
    assert.deepStrictEqual(rs.map((r) => [r.rep, r.var]), [[1, 'low'], [2, 'flee'], [3, 'outnum']]);
    const [a, b, c] = rs;
    assert.deepStrictEqual([a.target, a.released, a.hit1, a.hit2, a.gap, a.both, a.killed, a.kt, a.together], ['h8', 51, 1, 2, 1, 1, 1, 5, null]);
    assert.deepStrictEqual([b.hit1, b.hit2, b.gap, b.both, b.killed, b.last1, b.last2, b.ret1, b.ret2, b.together], [1, 6, 5, 0, 0, 8, 7, null, 9, 0]);
    assert.deepStrictEqual([c.control, c.attacked, c.target], [1, 0, null]);
    const sum = summary(rs);
    assert.deepStrictEqual(sum.low, { reps: 1, control: 0, attacked: 1, both: 1, kill: 1, together: '0 of 0' });
    assert.strictEqual(sum.flee.together, '0 of 1');
    assert.strictEqual(sum.outnum.attacked, 0);
});
