'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const seen = (t, team, cid, type, lane = 'bot') => line(t, `unit_seen team=${team} cid=${cid} kind=lane type=${type} lane=${lane} x=0 y=-6000`);
const gone = (t, team, cid, by = 'none', x = 0, y = -6000) => line(t, `unit_gone team=${team} cid=${cid} x=${x} y=${y} hp=0.1 by=${by}`);
const taker = (t, team, cid, by, tw = 0, x = 0, y = -6000, kind = 'melee') => line(t, `creep_death team=${team} kind=${kind} x=${x} y=${y} hp=0.05 by=${by} tw=${tw} cid=${cid}`);

// pid 1 (Radiant) stands at (x, y) every second from 60 to 130: an own creep is a deny chance only with a living hero of its team within 1,500
const stands = (x, y) => Array.from({ length: 71 }, (_, i) => line(60 + i, `snap pid=${1} x=${x} y=${y} alive=1 hp=100`));

function fates(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cfu-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, ['10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456', ...[...lines].sort((x, y) => at(x) - at(y))].join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const view = s.query('WITH gm AS (SELECT game_id FROM games),\n-- include: creep_fate\nSELECT seq, t, team, side, kind, x, y, fate, pid, tw FROM creep_fate ORDER BY t, side').map(r => ({ ...r }));
    const seqOf = ev => s.query(`SELECT seq, t, team FROM ev_${ev} ORDER BY seq`).map(r => ({ ...r }));
    return { view, creepDeath: seqOf('creep_death'), unitGone: seqOf('unit_gone'), s };
}

test('a game with unit_seen: the enemy side is a creep_death line paired to a creep found gone (its own seq), the own side every creep found gone; a sighting that was not a death is no row', () => {
    const { view, creepDeath, unitGone } = fates([
        seen(60, 2, 1, 'creep_goodguys_melee'), seen(60, 2, 2, 'creep_goodguys_ranged'), seen(60, 2, 3, 'creep_goodguys_flagbearer'), seen(60, 2, 4, 'creep_goodguys_melee'),
        gone(100, 2, 1), gone(110, 2, 2, 1), gone(120, 2, 3), // 2:1 taken by team 3's pid 5, 2:2 denied by pid 1, 2:3 a creep kill
        taker(100.3, 3, 40, 5, 0, 30, -6000),
        taker(110.3, 3, 41, 'none', 0, 0, -6000, 'ranged'),
        // team 3 saw 2:4 leave its list at low health and it lived: no unit_gone behind the line
        taker(300, 3, 42, 'none', 1, 900, -6000),
        ...stands(0, -6000),
    ]);
    const enemy = view.filter(r => r.side === 'enemy'), own = view.filter(r => r.side === 'own');
    assert.deepStrictEqual(enemy.map(r => [r.seq, r.t, r.team, r.kind, r.x, r.fate, r.pid, r.tw]), [
        [creepDeath[0].seq, 100.3, 3, 'melee', 30, 'own_lh', 5, 0],
        [creepDeath[1].seq, 110.3, 3, 'ranged', 0, 'enemy_deny', 1, 0],
    ], 'the lone sighting at 300 is not a death');
    assert.deepStrictEqual(own.map(r => [r.seq, r.t, r.team, r.kind, r.fate, r.pid]), [
        [unitGone[0].seq, 100, 2, 'melee', 'lost', null],
        [unitGone[1].seq, 110, 2, 'ranged', 'own_deny', 1],
        [unitGone[2].seq, 120, 2, 'melee', 'lost', null],
    ], 'a flag bearer is a melee creep, and every creep found gone is a row whether or not a hero was near');
});

test('a game without unit_seen reads the death events exactly as before, however a unit_seen game is read beside it', () => {
    const { view } = fates([
        line(100, 'creep_death team=3 kind=melee x=0 y=0 hp=0.1 by=5 tw=0'),
        line(110, 'creep_death team=3 kind=melee x=300 y=0 hp=0.1 by=none tw=0'),
        line(110.2, 'own_creep_death team=2 kind=melee x=320 y=0 hp=0.1 by=1'),
        line(120, 'own_creep_death team=2 kind=melee x=0 y=0 hp=0.1 by=none'),
        ...stands(0, 0),
    ]);
    assert.deepStrictEqual(view.map(r => [r.t, r.side, r.fate, r.pid]), [[100, 'enemy', 'own_lh', 5], [110, 'enemy', 'enemy_deny', 1], [110.2, 'own', 'own_deny', 1], [120, 'own', 'lost', null]]);
});

test('timeline creep rows of a unit_seen game: a hero\'s last hit and deny, and a creep nobody got in the lane where it died', () => {
    const { s } = fates([
        line(0, 'player pid=1 team=2'),
        seen(60, 2, 1, 'creep_goodguys_melee'), seen(60, 2, 2, 'creep_goodguys_melee'),
        gone(100, 2, 1, 'none', 0, -6000), gone(110, 2, 2, 'none', 0, -6000),
        taker(100.3, 3, 40, 'none', 1, 0, -6000),
        ...stands(0, -6000),
    ]);
    const rows = s.query(`WITH
-- include: timeline_rows
SELECT t, detail, what, outcome, lane FROM timeline_rows WHERE kind = 'creep' ORDER BY t`, { like: '%', batch: null, arm: null, game: null, lane: null, hero: null, pid: null, from: null, to: null, kind: null });
    assert.deepStrictEqual(rows.map(r => [r.t, r.outcome, r.lane]), [[100.3, 'other', 'bot'], [110, 'lost', 'bot']]);
});

test('the own side keeps its meaning: a creep is a deny chance only if it died at half health or less within 1,500 of a living hero of its team', () => {
    const { view } = fates([
        seen(60, 2, 1, 'creep_goodguys_melee'), seen(60, 2, 2, 'creep_goodguys_melee'), seen(60, 2, 3, 'creep_goodguys_melee'), seen(60, 2, 4, 'creep_goodguys_melee'),
        gone(100, 2, 1, 'none', 0, -6000),                      // near the hero, low: a row
        line(101, 'unit_gone team=2 cid=2 x=0 y=-6000 hp=0.9 by=none'), // near, healthy: no row
        gone(102, 2, 3, 'none', 4000, 4000),                    // 10,000 from the hero: no row
        gone(103, 2, 4, 'none', 0, -6000),                      // the hero stood there, but dead: no row
        line(102, 'snap pid=1 x=0 y=-6000 alive=0 hp=0'),
        ...Array.from({ length: 41 }, (_, i) => line(60 + i, 'snap pid=1 x=0 y=-6000 alive=1 hp=100')),
    ]);
    assert.deepStrictEqual(view.filter(r => r.side === 'own').map(r => r.t), [100]);
});
