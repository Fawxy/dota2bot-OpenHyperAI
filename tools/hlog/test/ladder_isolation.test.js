'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { rows, verdicts, laneOf } = require('../ladder_isolation');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const N = 'ladder-duel';

function store(lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-li-'));
    const f = path.join(dir, 'drill_ladder-duel_t.log');
    const at = (l) => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}

const snap = (t, pid, x, y, tid) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=80 mode=laning lh=0 dn=0 deaths=0${tid ? ` tid=${tid}` : ''}`);
const role = (t, pid, team, pos, r) => line(t, `drill ph=role name=${N} pid=${pid} team=${team} pos=${pos} role=${r}`);

test('laneOf: safe, mid and off lanes per side', () => {
    assert.deepStrictEqual([laneOf(2, 1), laneOf(2, 2), laneOf(2, 3), laneOf(3, 1), laneOf(3, 4), laneOf(3, 5)], ['bot', 'mid', 'top', 'top', 'bot', 'top']);
});

test('ladder_isolation: seconds out of lane, at base, attacked from another lane; benched heroes are not rows', () => {
    const l = [
        line(0, 'bot pid=1 hero=sniper team=2 pos=2'), line(0, 'bot pid=6 hero=zuus team=3 pos=2'), line(0, 'bot pid=0 hero=luna team=2 pos=1'),
        line(0, 'bot pid=9 hero=lich team=3 pos=5'),
        role(0.5, 1, 2, 2, 'cast'), role(0.5, 6, 3, 2, 'cast'), role(0.5, 0, 2, 1, 'cast'), role(0.5, 9, 3, 5, 'bench'),
    ];
    for (let t = 1; t <= 20; t++) {
        // Our mid stands mid for 10 s, then 10 s in the top lane.
        l.push(t <= 10 ? snap(t, 1, 0, 0) : snap(t, 1, -6200, 3000));
        // Their mid stays mid, attacking our mid from 5 to 8 (its own lane: not cross).
        l.push(snap(t, 6, 200, 200, t >= 5 && t <= 8 ? 'h1' : ''));
        // Our safe core: bot lane, 4 s off the band at the map's south edge (nearest still bot), then 3 s in the fountain.
        l.push(t <= 13 ? snap(t, 0, 3000, -6200) : t <= 17 ? snap(t, 0, 3000, -7600) : snap(t, 0, -6850, -6461));
        // The benched Dire pos5 (top lane) hits our safe core (bot) from 12 to 14: cross.
        l.push(snap(t, 9, 3100, -6200, t >= 12 && t <= 14 ? 'h0' : ''));
    }
    const r = rows(store(l), 'ladder-duel');
    const by = Object.fromEntries(r.map((x) => [x.pid, x]));
    assert.strictEqual(r.length, 3);
    assert.strictEqual(by[1].lane, 'mid');
    assert.strictEqual(by[1].away, 10);
    assert.strictEqual(by[1].cross, 0);
    assert.strictEqual(by[0].lane, 'bot');
    assert.strictEqual(by[0].base, 3);
    assert.strictEqual(by[0].away, 0);
    assert.strictEqual(by[0].off, 4);
    assert.strictEqual(by[0].cross, 3);
    const v = verdicts(r);
    assert.strictEqual(v.length, 1);
    assert.strictEqual(v[0].ok, 0);
    assert.strictEqual(v[0].cross, 3);
});
