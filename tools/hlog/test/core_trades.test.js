'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { TOWERS } = require('../dynamic');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

function run(name, lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-trade-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql(name), params);
    s.db.close();
    return out;
}

const trade = (t, result, hpd, thpd, dur = 2, ag = 0) => line(t, `trade pid=1 kind=trade tgt=6 result=${result} why=losing dur=${dur} hpd=${hpd} thpd=${thpd} hp=0.8 thp=0.7 en=1 al=1 cr=1 ag=${ag} mode=2`);

test('core trades: taken, won, aggroed and lost windows per core; trades past until and support rows are not counted', () => {
    const out = run('core_trades', [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=4 hero=h4 team=2 pos=4'),
        line(100, 'snap pid=1 x=0 y=0 alive=1 mode=attack tgt=npc_dota_hero_x deaths=0 ol=0 ar=500 ed=400'),
        line(101, 'snap pid=1 x=0 y=0 alive=1 mode=laning deaths=1 ol=0 ar=500 ed=400'),
        line(100, 'snap pid=4 x=0 y=0 alive=1 mode=laning deaths=0'),
        trade(110, 'done', 50, 120),
        trade(120, 'done', 90, 40, 2, 2),
        trade(130, 'kill', 30, 200),
        trade(140, 'lost', 0, 0, 0),
        trade(700, 'done', 1, 100),
    ]);
    assert.deepStrictEqual(out.map(r => [r.pid, r.taken, r.won, r.kills, r.lost, r.hpd, r.thpd, r.aggroed, r.hero, r.trade_open, r.trade_open_hero, r.deaths]),
        [[1, 3, 2, 1, 1, 170, 360, 1, 1, 2, 1, 1]]);
});

test('core deaths: each death of a core before until gets the first matching cause', () => {
    const snaps = [];
    // No snaps while dead: a death is the last snap before the count rises (the respawn snap 30 s later). pid 1 dies at 145 during a
    // trade, at 244 after a retreat cut back to the last-hit desire, at 345 under the Dire mid T1, at 445 laning, at 545 farming;
    // at 645, past until.
    const at = (t, mode, deaths, x = 0, y = -3000, d = 0.4) => snaps.push(line(t, `snap pid=1 x=${x} y=${y} alive=1 hp=30 mode=${mode} d=${d} deaths=${deaths}`));
    at(140, 'laning', 0); at(145, 'laning', 0); at(175, 'laning', 1);
    at(240, 'retreat', 1); at(244, 'laning', 1, 0, -3000, 0.9); at(274, 'laning', 2);
    at(345, 'laning', 2, 524, 600); at(375, 'laning', 3);
    at(445, 'laning', 3); at(475, 'laning', 4);
    at(545, 'farm', 4); at(575, 'farm', 5);
    at(645, 'laning', 5); at(675, 'laning', 6);
    const out = run('core_deaths', [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), ...snaps, trade(146, 'done', 300, 50, 3)]);
    assert.deepStrictEqual(out.map(r => [r.t, r.cause]), [[145, 'trade'], [244, 'cut'], [345, 'tower'], [445, 'lane'], [545, 'farm']]);
});

test('core deaths: the tower table equals dynamic.js TOWERS', () => {
    const values = sql('core_deaths').match(/tw \(team, x, y\) AS \(VALUES([\s\S]*?\))\),/)[1];
    const rows = [...values.matchAll(/\((\d), (-?\d+), (-?\d+)\)/g)].map(m => m.slice(1).map(Number));
    assert.deepStrictEqual(rows, TOWERS);
});
