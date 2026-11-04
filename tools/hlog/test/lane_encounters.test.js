'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const snap = (t, pid, o) => line(t, `snap pid=${pid} x=${o.x ?? 0} y=${o.y ?? 0} alive=1 hp=${o.hp ?? 100} deaths=${o.deaths ?? 0}`
    + ` mode=${o.mode ?? 'laning'} d=0.5${o.ed !== undefined ? ` ed=${o.ed}` : ''} by="${o.mode ?? 'laning'} 0.50 by raw"`);

test('lane encounters: numbers and enemy HP at the start, a kill near the hero and its own death dated before the dead gap', () => {
    const lines = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=4 hero=h4 team=2 pos=4'),
        line(0, 'bot pid=6 hero=h6 team=3 pos=3'),
        line(0, 'bot pid=7 hero=h7 team=3 pos=2'),
    ];
    // Encounter 1: core with its support beside it against one enemy at 30% HP, team roam holding; the enemy dies at 103 (its
    // snaps stop, the next one at 125 carries the death), so the kill is dated 103, inside the encounter.
    for (let t = 100; t <= 103; t++) {
        lines.push(snap(t, 1, { ed: 500, mode: 'team_roam', hp: 100 - (t - 100) * 5 }));
        lines.push(snap(t, 4, { x: 300 }));
        lines.push(snap(t, 6, { x: 500, hp: 30 }));
        lines.push(snap(t, 7, { x: 5000, y: 5000 }));
    }
    lines.push(snap(125, 6, { x: 7000, y: 7000, deaths: 1 }));
    // Encounter 2: the core alone against both enemies at full HP, laning; it dies at 202 (respawn snap at 230).
    for (let t = 200; t <= 202; t++) {
        lines.push(snap(t, 1, { x: 1000, ed: 400, hp: 90 }));
        lines.push(snap(t, 4, { x: 6000, y: -6000 }));
        lines.push(snap(t, 6, { x: 1400, deaths: 1 }));
        lines.push(snap(t, 7, { x: 1500, deaths: 0 }));
    }
    lines.push(snap(230, 1, { x: -7000, y: -7000, deaths: 1 }));
    // Outside :until: not read.
    lines.push(snap(700, 1, { ed: 300 }), snap(701, 1, { ed: 300 }));
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-enc-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lane_encounters.sql'), 'utf8');
    const rows = s.query(sql, {}).map(r => [r.role, r.numbers, r.ehp, r.held, r.enc, r.kills, r.deaths, r.hp_drop]);
    assert.deepStrictEqual(rows, [
        ['core', 'fewer', '>70', 'other', 1, 0, 1, 0],
        ['core', 'more', '<=40', 'roam', 1, 1, 0, 15],
    ]);
    s.db.close();
});
