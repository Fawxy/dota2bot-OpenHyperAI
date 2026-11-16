'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

// Slice high-stand: the view @high_stand (queries/high_stand.sql).
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const query = fs.readFileSync(path.join(__dirname, '..', 'queries', 'high_stand.sql'), 'utf8');
const PX = -2000, PY = 3000;

const bots = heroes => heroes.map(([pid, team, pos]) => line(0, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos} ours=Threat:${team === 2 ? 1 : 0}`));
const snap = (t, pid, x, y, o = {}) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${o.hp ?? 100} mode=${o.mode ?? 'laning'} ` +
    `lvl=3 deaths=0 ar=${o.ar ?? 550} ld=0 hit=${o.hit ?? 0}`);

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-hstand-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(query, {}).filter(r => r.pid === 1).map(r => [r.t, r.ret, r.ret_nohit, r.died, r.even]);
    s.db.close();
    return out;
}

/** Our pid 1 at full HP with two enemy heroes 700 off from 100 to 110; `o` sets its HP, and its mode and hit flag per second. */
function game(o = {}) {
    const lines = bots([[1, 2, 1], [6, 3, 1], [7, 3, 5]]);
    for (let t = 100; t <= 110; t++) {
        lines.push(snap(t, 1, PX, PY, { hp: o.hp ?? 100, mode: o.mode ? o.mode(t) : 'laning', hit: o.hit ? o.hit(t) : 0 }));
        lines.push(snap(t, 6, PX + 700, PY), snap(t, 7, PX + 700, PY + 100));
    }
    return lines;
}

test('high stand: one onset per spell; a retreat with no hit is the violation, one after a hit is not ret_nohit', () => {
    assert.deepStrictEqual(run(game()), [[100, 0, 0, 0, 0]]);
    assert.deepStrictEqual(run(game({ mode: t => (t >= 102 ? 'retreat' : 'laning') })), [[100, 1, 1, 0, 0]]);
    assert.deepStrictEqual(run(game({ mode: t => (t >= 102 ? 'retreat' : 'laning'), hit: t => (t >= 101 ? 1 : 0) })), [[100, 1, 0, 0, 0]]);
});

test('high stand: under 70% HP, or hit throughout, is no situation', () => {
    assert.deepStrictEqual(run(game({ hp: 60 })), []);
    assert.deepStrictEqual(run(game({ hit: () => 1 })), []);
});
