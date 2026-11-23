'use strict';
// The lane denies line (queries/deny_reach.sql, deny_reach_games.sql, fragment deny_reach_rows): own lane creeps that died with a
// side-lane support in or just outside reach, and who took them. Radiant juggernaut (pid 0, pos 1) and lich (pid 1, pos 5);
// Dire sniper (pid 5, pos 2), on a synthetic game. Lich's attack range is 550: in reach to 898, near to 1,198.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const snap = (t, pid, x, { alive = 1, ln = 'bot', ar = 550, od = 0 } = {}) =>
    line(t, `snap pid=${pid} x=${x} y=0 alive=${alive} hp=100 ar=${ar} od=${od} ln=${ln}`);
const own = (t, by, cid) => line(t, `own_creep_death team=2 kind=melee x=0 y=0 hp=0.3 by=${by} cid=${cid}`);
const enemyView = (t, by, x = 40) => line(t, `creep_death team=3 kind=melee x=${x} y=0 hp=0.3 by=${by}`);

/**
 * 100  lich at 100, denies it             in    sup_deny
 * 110  lich at 850, juggernaut denies     in    own_deny
 * 120  lich at 1,100; sniper's last hit   near  enemy_lh
 * 130  lich at 1,300                      no row (beyond near)
 * 140  lich dead                          no row
 * 150  lich in mid                        no row
 * 160  lich's last snap 3 s old           no row
 * 170  lich at 200; no one's              in    other (the enemy row names no one)
 * 700  after :until                       no row
 */
function gameLines() {
    return [
        line(-90, 'bot pid=0 hero=juggernaut team=2 pos=1'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=sniper team=3 pos=2'),
        snap(99.5, 0, 50), snap(99.5, 1, 100, { od: 1 }), own(100, 1, 1),
        snap(109.8, 1, 850), own(110, 0, 2),
        snap(119.6, 1, 1100), own(120, 'none', 3), enemyView(120.3, 5),
        snap(129.6, 1, 1300), own(130, 'none', 4),
        snap(139.6, 1, 100, { alive: 0 }), own(140, 'none', 5),
        snap(149.6, 1, 100, { ln: 'mid' }), own(150, 'none', 6),
        snap(157, 1, 100), own(160, 'none', 7),
        snap(169.6, 1, 200), own(170, 'none', 8), enemyView(170.2, 'none'),
        snap(699.6, 1, 100), own(700, 1, 9),
    ];
}

function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-deny-reach-'));
    const file = path.join(dir, '2026-11-24T00-00-00-dr_A_off_1.log');
    fs.writeFileSync(file, gameLines().join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}
const sqlOf = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

test('deny_reach: a row per own creep death with a side-lane support in or near reach, and its fate', () => {
    const store = load();
    const rows = store.query(sqlOf('deny_reach'), { like: '%dr_A_off_1%', until: 600 }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.t, r.pid, r.pos, r.dist, r.band, r.fate]), [
        [100, 1, 5, 100, 'in', 'sup_deny'],
        [110, 1, 5, 850, 'in', 'own_deny'],
        [120, 1, 5, 1100, 'near', 'enemy_lh'],
        [170, 1, 5, 200, 'in', 'other'],
    ]);
    assert.strictEqual(rows[0].offers, 1);
});

test('deny_reach_games: the shares per team-game and band', () => {
    const store = load();
    const rows = store.query(sqlOf('deny_reach_games'), { like: '%dr_A_off_1%', until: 600 }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.team, r.band, r.n, r.sup, r.den, r.elh, r.den_share, r.sup_share, r.elh_share]), [
        [2, 'in', 3, 1, 2, 0, 0.667, 0.333, 0],
        [2, 'near', 1, 0, 0, 1, 0, 0, 1],
    ]);
});
