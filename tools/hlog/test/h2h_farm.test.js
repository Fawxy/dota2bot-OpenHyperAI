'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'h2h_farm.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-h2hfarm-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out.map(r => [r.side, r.team, r.nw, r.lh, r.dn, r.kills, r.deaths, r.lvl, r.core_lh]);
}

// Ours on Radiant: pos 1 and pos 5; OHA on Dire: pos 2 and pos 4.
const bots = [[1, 2, 1], [5, 2, 5], [6, 3, 2], [9, 3, 4]].map(([pid, team, pos]) =>
    line(0, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos} ours=Threat:${team === 2 ? 1 : 0}`));
const snap = (t, pid, o) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=100 lvl=${o.lvl} lh=${o.lh} dn=${o.dn ?? 0} ` +
    `kills=${o.k ?? 0} deaths=${o.d ?? 0}` + (o.nw === undefined ? '' : ` nw=${o.nw}`));

test('sums each team at the last snapshot at or before :at, cores only in core_lh', () => {
    const lines = [...bots];
    for (const [pid, base] of [[1, 40], [5, 4], [6, 30], [9, 2]]) {
        lines.push(snap(590, pid, { lvl: 6, lh: base - 1, nw: 1000 * base }));
        lines.push(snap(600, pid, { lvl: 7, lh: base, dn: 1, k: pid === 6 ? 2 : 0, d: pid === 5 ? 3 : 0, nw: 100 * base + 500 }));
        lines.push(snap(610, pid, { lvl: 8, lh: base + 5, nw: 99999 }));
    }
    assert.deepStrictEqual(run(lines), [
        ['ours', 2, 4500 + 900, 44, 2, 0, 3, 7, 40],
        ['oha', 3, 3500 + 700, 32, 2, 2, 0, 7, 30],
    ]);
    // At 5:00 nobody has a snapshot yet: no rows.
    assert.deepStrictEqual(run(lines, { at: 300 }), []);
});

test('a team with a hero that logged no net worth gets NULL net worth, its counts still summed', () => {
    const lines = [...bots, snap(600, 1, { lvl: 7, lh: 40, nw: 4000 }), snap(600, 5, { lvl: 7, lh: 4 }),
        snap(600, 6, { lvl: 7, lh: 30, nw: 3000 }), snap(600, 9, { lvl: 7, lh: 2, nw: 700 })];
    assert.deepStrictEqual(run(lines).map(r => [r[0], r[2], r[3]]), [['ours', null, 44], ['oha', 3700, 32]]);
});
