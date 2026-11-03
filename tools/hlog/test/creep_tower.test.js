'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'creep_tower.sql'), 'utf8');

function rows(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ctw-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

test('a tower creep counts as the tower\'s only when no one got it, in reach only within a core\'s range + 100; our last hits and enemy denies under the tower are split out', () => {
    const out = rows([
        // Tower kill with the pos 1 core at range + 80: in reach.
        line(100, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=1 p1d=630 p1r=550'),
        // Tower kill with the core at range + 300: not in reach.
        line(110, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=1 p1d=850 p1r=550'),
        // Our last hit under the tower.
        line(120, 'creep_death team=2 kind=ranged x=0 y=0 hp=0.05 by=1 tw=1 p1d=500 p1r=550'),
        // An enemy deny under the tower: named from the other team's own_creep_death.
        line(130, 'creep_death team=2 kind=melee x=1000 y=1000 hp=0.05 by=none tw=1 p1d=400 p1r=550'),
        line(130, 'own_creep_death team=3 kind=melee x=1000 y=1000 hp=0.05 by=7'),
        // Open lane, no tower: in deaths only.
        line(140, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=0 p1d=400 p1r=550'),
        // An older build with no tw field.
        line(150, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none'),
        line(700, 'creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none tw=1 p1d=400 p1r=550'),
    ]);
    assert.strictEqual(out.length, 1);
    const r = out[0];
    assert.deepStrictEqual([r.deaths, r.tw_deaths, r.tower, r.tower_reach, r.tw_lh, r.tw_denied, r.untagged], [6, 4, 2, 1, 1, 1, 1]);
});
