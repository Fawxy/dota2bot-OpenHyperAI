'use strict';
// The lane creeps family's line (queries/creep_paid.sql, creep_paid_games.sql, fragment creep_paid_rows): who was paid for each lane
// creep death, read from each team's side, and that team's reach at the death. A synthetic unit_seen game in mid: Radiant sniper
// (pid 0, pos 2, range 550) and lion (pid 1, pos 5, range 600), Dire zuus (pid 5, pos 2, range 500). In reach: gap = dist - (ar + 48).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const seen = (team, cid, type) => line(60, `unit_seen team=${team} cid=${cid} kind=lane type=${type} lane=mid x=0 y=0`);
const gone = (t, team, cid, by = 'none', x = 0, y = 0) => line(t, `unit_gone team=${team} cid=${cid} x=${x} y=${y} hp=0.1 by=${by}`);
const taker = (t, team, cid, by, kind, { tw = 0, x = 0, y = 0 } = {}) =>
    line(t, `creep_death team=${team} kind=${kind} x=${x} y=${y} hp=0.05 by=${by} tw=${tw} cid=${cid}`);
const snap = (t, pid, x, { ar = 550, alive = 1, tid, ed } = {}) =>
    line(t, `snap pid=${pid} x=${x} y=0 alive=${alive} hp=90 ar=${ar}${tid ? ` tid=${tid}` : ''}${ed ? ` ed=${ed}` : ''}`);

/**
 * Dire's creeps (Radiant's `theirs`), and one of Radiant's:
 * A 100    Dire ranged, sniper's last hit; sniper 400 away with a target         paid us, in
 * B 110    Dire melee, zuus denies; no Radiant snapshot within 1.5 s              nobody, none
 * C 120    Dire ranged under Radiant's tower; sniper 500 at 119.1 but 1,400 at 120 (between snapshots), lion 1,000: lion nearest
 * D 130    Dire melee, nobody; sniper 700 away and last-hits E 0.5 s later       nobody, r150, busy
 * E 130.5  Dire melee at (100, 100), sniper's last hit, 806 away                   paid us, r300
 * F 140    Radiant ranged, zuus's last hit; sniper dead, lion too far            paid them, none (Dire: paid us, zuus in at 300)
 * G 700    after until                                                           no row
 */
function gameLines() {
    return [
        line(-90, 'bot pid=0 hero=sniper team=2 pos=2'),
        line(-90, 'bot pid=1 hero=lion team=2 pos=5'),
        line(-90, 'bot pid=5 hero=zuus team=3 pos=2'),
        ...[1, 3].map(c => seen(3, c, 'npc_dota_creep_badguys_ranged')),
        ...[2, 4, 5, 7].map(c => seen(3, c, 'npc_dota_creep_badguys_melee')),
        seen(2, 6, 'npc_dota_creep_goodguys_ranged'),
        snap(99.5, 0, -400, { tid: 'u1' }), snap(100.5, 0, -400),
        gone(100, 3, 1), taker(100, 2, 41, 0, 'ranged'),
        gone(110, 3, 2, 5), taker(110, 2, 42, 'none', 'melee'),
        snap(119.1, 0, -500), snap(120.1, 0, -1500), snap(119.1, 1, -1000, { ar: 600 }), snap(120.1, 1, -1000, { ar: 600 }),
        gone(120, 3, 3), taker(120, 2, 43, 'none', 'ranged', { tw: 1 }),
        snap(129.5, 0, -700, { ed: 900 }), snap(130.8, 0, -700),
        gone(130, 3, 4), taker(130, 2, 44, 'none', 'melee'),
        gone(130.5, 3, 5, 'none', 100, 100), taker(130.5, 2, 45, 0, 'melee', { x: 100, y: 100 }),
        snap(139.5, 0, -400, { alive: 0 }), snap(140.5, 0, -400, { alive: 0 }), snap(139.5, 1, -1700, { ar: 600 }),
        snap(139.5, 5, 300, { ar: 500 }), snap(140.5, 5, 300, { ar: 500 }),
        gone(140, 2, 6), taker(140, 3, 46, 5, 'ranged'),
        snap(699.5, 0, -100), gone(700, 3, 7), taker(700, 2, 47, 0, 'melee'),
    ];
}

function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-creep-paid-'));
    const file = path.join(dir, '2026-11-25T00-00-00-cp_A_off_1.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(file, gameLines().sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}
const sqlOf = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');
const like = '%cp_A_off_1%';

test('creep_paid: each death once per team, who was paid, and the reach from places between snapshots', () => {
    const rows = load().query(sqlOf('creep_paid'), { like }).map(r => ({ ...r }));
    const rad = rows.filter(r => r.team === 2);
    assert.deepStrictEqual(rad.map(r => [r.t, r.whose, r.kind, r.lane, r.how, r.paid, r.tw, r.pid, r.dist, r.band, r.busy]), [
        [100, 'theirs', 'ranged', 'mid', 'lh', 'us', 0, 0, 400, 'in', 0],
        [110, 'theirs', 'melee', 'mid', 'deny', 'nobody', 0, null, null, 'none', null],
        [120, 'theirs', 'ranged', 'mid', 'tower', 'nobody', 1, 1, 1000, 'r1500', 0],
        [130, 'theirs', 'melee', 'mid', 'other', 'nobody', 0, 0, 700, 'r150', 1],
        [130.5, 'theirs', 'melee', 'mid', 'lh', 'us', 0, 0, 806, 'r300', 0],
        [140, 'ours', 'ranged', 'mid', 'lh', 'them', 0, null, null, 'none', null],
    ]);
    assert.deepStrictEqual([rad[0].atk, rad[3].atk, rad[3].ed], [1, 0, 900], 'target and enemy distance from the snapshot at or before the death');
    assert.deepStrictEqual([rad[2].cpid, rad[2].cgap, rad[2].cband], [0, 802, 'r1500'], 'the nearest core beside the nearest hero');
    assert.deepStrictEqual(rows.filter(r => r.team === 3).map(r => [r.t, r.whose, r.paid, r.pid, r.band]), [
        [100, 'ours', 'them', null, 'none'],
        [110, 'ours', 'nobody', null, 'none'],
        [120, 'ours', 'nobody', null, 'none'],
        [130, 'ours', 'nobody', null, 'none'],
        [130.5, 'ours', 'them', null, 'none'],
        [140, 'theirs', 'us', 5, 'in'],
    ]);
});

test('creep_paid_games: the line per team-game, and a cell by filters', () => {
    const store = load();
    const cols = r => [r.team, r.n, r.us, r.them, r.nobody, r.theirs, r.t_lh, r.t_dn, r.t_tower, r.t_other, r.ours, r.o_lh, r.o_dn];
    assert.deepStrictEqual(store.query(sqlOf('creep_paid_games'), { like }).map(cols), [
        [2, 6, 2, 1, 3, 5, 2, 1, 1, 1, 1, 1, 0],
        [3, 6, 1, 2, 3, 1, 1, 0, 0, 0, 5, 2, 1],
    ]);
    const ranged = store.query(sqlOf('creep_paid_games'), { like, kind: 'ranged', whose: 'theirs', band: 'in,r150,r300,r1500' });
    assert.deepStrictEqual(ranged.map(r => [r.team, r.n, r.us, r.nobody, r.sh_us]), [[2, 2, 1, 1, 0.5], [3, 1, 1, 0, 1]]);
    assert.deepStrictEqual(store.query(sqlOf('creep_paid_games'), { like, cband: 'none' }).map(r => [r.team, r.n]), [[2, 2], [3, 5]]);
    assert.deepStrictEqual(store.query(sqlOf('creep_paid_games'), { like, kind: 'melee', whose: 'ours' }).map(r => [r.team, r.n, r.them, r.sh_us]),
        [[2, 0, 0, null], [3, 3, 1, 0]], 'a team-game with nothing in the cell still has its row, a zero');
});
