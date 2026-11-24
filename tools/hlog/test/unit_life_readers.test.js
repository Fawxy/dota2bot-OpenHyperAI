'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const bots = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=1')];
const snap = (t, pid, x, y, alive = 1) => line(t, `snap pid=${pid} x=${x} y=${y} alive=${alive} hp=100`);

function store(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ulr-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...bots, ...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}
const OWN = `WITH ul_gm AS (SELECT game_id FROM games),
-- include: unit_life_in
-- include: unit_life_lane
SELECT t, kind, dny, cd_seq IS NULL AS untaken FROM ul_odeath ORDER BY t`;
const NEU = `WITH ul_gm AS (SELECT game_id FROM games),
-- include: unit_life_in
-- include: unit_life_seen
-- include: unit_life_neutral
SELECT t1, camp, by_pid, near_r, near_d FROM ul_nlife WHERE t1 IS NOT NULL ORDER BY t1`;

test('ul_odeath: the owner\'s deny stays its denier when the taker\'s line says a tower hit it; a creep with no hero of its team near, or over half health, is not a deny chance', () => {
    const s = store([
        // old events: a deny by pid 1 whose enemy line has tw=1; a loss by an enemy hero; one with no hero near; one at 80% health
        line(100, 'own_creep_death team=2 kind=melee x=0 y=0 hp=0.2 by=1'), line(100.2, 'creep_death team=3 kind=melee x=10 y=0 hp=0.2 by=none tw=1'),
        line(110, 'own_creep_death team=2 kind=melee x=300 y=0 hp=0.2 by=none'), line(110.2, 'creep_death team=3 kind=melee x=310 y=0 hp=0.2 by=6 tw=0'),
        line(120, 'own_creep_death team=2 kind=melee x=9000 y=9000 hp=0.2 by=none'),
        line(130, 'own_creep_death team=2 kind=melee x=0 y=0 hp=0.8 by=none'),
        snap(99.5, 1, 0, 0), snap(109.5, 1, 0, 0), snap(119.5, 1, 0, 0), snap(129.5, 1, 0, 0),
    ]);
    assert.deepStrictEqual(s.query(OWN).map(r => [r.t, r.dny, r.untaken]), [[100, 1, 0], [110, null, 0]]);
    s.db.close();
});

test('ul_odeath on a unit_seen game: the same gate from the snapshots, a creep still alive is no row, and a creep only the owner logged has no taker line', () => {
    const seen = (t, cid) => line(t, `unit_seen team=2 cid=${cid} kind=lane type=creep_goodguys_melee lane=bot x=0 y=0`);
    const gone = (t, cid, by, hp = 0.1) => line(t, `unit_gone team=2 cid=${cid} x=0 y=0 hp=${hp} by=${by}`);
    const s = store([
        seen(60, 1), seen(60, 2), seen(60, 3), seen(60, 4),
        gone(100, 1, 1), gone(110, 2, 'none'), gone(120, 3, 'none', 0.9),
        line(110.2, 'creep_death team=3 kind=melee x=5 y=0 hp=0.1 by=6 tw=0 cid=40'),
        snap(99.5, 1, 0, 0), snap(109.5, 1, 0, 0), snap(119.5, 1, 0, 0),
    ]);
    assert.deepStrictEqual(s.query(OWN).map(r => [r.t, r.dny, r.untaken]), [[100, 1, 1], [110, null, 0]],
        'cid 3 died at 90% health; cid 4 is alive');
    s.db.close();
});

test('ul_nlife: a team\'s own neutral deaths are the units its module saw die with a hero of the team within 1,500; a neutral the other team alone saw is not Radiant\'s', () => {
    const s = store([
        // old events. 100: both teams' lines, pid 1 took it. 110: only Radiant's line (by none) while a Dire hero stands there: not Dire's.
        line(100, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.1 by=1 camp=1'), line(100.1, 'neutral_death team=3 kind=neutral x=5 y=0 hp=0.1 by=none camp=1'),
        line(110, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.1 by=none camp=1'),
        snap(99.5, 1, 0, 0), snap(99.5, 6, 100, 0), snap(109.5, 1, 0, 0), snap(109.5, 6, 100, 0),
    ]);
    assert.deepStrictEqual(s.query(NEU).map(r => [r.t1, r.by_pid, r.near_r, r.near_d]), [[100, 1, 1, 1], [110, null, 1, 0]]);
    s.db.close();
});

test('ul_nlife on a unit_seen game: only neutrals found dead are rows with a time, and Radiant\'s flag needs a Radiant hero near the spot', () => {
    const seen = (t, team, cid) => line(t, `unit_seen team=${team} cid=${cid} kind=neutral type=npc_dota_neutral_kobold x=0 y=0 camp=1`);
    const gone = (t, team, cid, by = 'none') => line(t, `unit_gone team=${team} cid=${cid} x=0 y=0 hp=0.1 by=${by}`);
    const s = store([
        seen(50, 2, 1), seen(50, 3, 1), seen(50, 2, 2), seen(50, 3, 2),
        gone(100, 2, 1, 1), gone(100.2, 3, 1),   // unit 1: both teams saw it die, pid 1 took it
        snap(99.5, 1, 0, 0), snap(99.5, 6, 9000, 9000),
        // unit 2 is never found dead: two rows at most, none with a time
    ]);
    assert.deepStrictEqual(s.query(NEU).map(r => [r.t1, r.by_pid, r.near_r, r.near_d]), [[100, 1, 1, 0]], 'the Dire hero stands 12,000 away');
    s.db.close();
});
