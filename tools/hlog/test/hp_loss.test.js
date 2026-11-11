'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { TOWERS } = require('../dynamic');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const BOTS = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=1')];

function open(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-hploss-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}

function rows(lines) {
    const s = open(lines);
    const out = s.query('SELECT * FROM hp_loss ORDER BY t');
    s.db.close();
    return out;
}

// Far from every tower, camp and front unless a case moves it.
const OPEN = 'x=0 y=-2500';
const api = (t, hp, extra) => line(t, `snap pid=1 ${OPEN} alive=1 hp=${hp} hv=${hp * 6} deaths=0 hit=0 hc=0 ht=0 ah=0 ac=0 an=0 at=0 ${extra || ''}`);

test('hp loss, api basis: each second of loss names the sources the flags and attackers state', () => {
    // Each case is its own pair ten seconds apart, so one case's attackers do not carry into the next.
    const cases = [
        ['hit=1 ah=1', 'hero'],
        ['hc=1 ac=2', 'creep'],
        ['hc=1 an=1', 'neutral'],
        ['an=1', 'neutral'],                    // no flag at all: the neutral is still the only source
        ['hit=1 an=1', 'hero'],                 // a neutral attacking, but a hero flagged and no creep flag
        ['hc=1', 'unit'],                       // creep flag, nobody seen attacking
        ['ht=1 hit=1 hc=1 ac=1 at=1', 'hero+tower+creep'],
        ['', 'unexplained'],
    ];
    const lines = [...BOTS];
    cases.forEach(([extra], i) => lines.push(api(100 + 10 * i, 100), api(101 + 10 * i, 95, extra)));
    lines.push(api(200, 60), api(201, 60), api(202, 62));   // no loss, then a gain: no rows
    const out = rows(lines).map(r => [r.basis, r.src, r.loss, r.loss_hp]);
    assert.deepStrictEqual(out, cases.map(([, src]) => ['api', src, 5, 30]));
});

test('hp loss, api basis: an attacker seen on the earlier snapshot of the pair still counts', () => {
    const out = rows([...BOTS, api(100, 100, 'ac=1'), api(101, 95, 'hc=1')]);
    assert.deepStrictEqual(out.map(r => [r.src, r.ac]), [['creep', 1]]);
});

test('hp loss: a death is one row at the last live snapshot with what was left, not a loss across the dead gap', () => {
    const out = rows([...BOTS,
        api(100, 40),
        api(101, 30, 'ht=1 at=1'),
        line(140, `snap pid=1 ${OPEN} alive=1 hp=100 hv=600 deaths=1 hit=0 hc=0 ht=0 ah=0 ac=0 an=0 at=0`),
        line(141, `snap pid=1 ${OPEN} alive=1 hp=90 hv=540 deaths=1 hit=1 hc=0 ht=0 ah=1 ac=0 an=0 at=0`),
    ]).map(r => [Math.round(r.t), r.died, r.src, r.loss]);
    assert.deepStrictEqual(out, [[101, 0, 'tower', 10], [101, 1, 'tower', 30], [141, 0, 'hero', 10]]);
});

test('hp loss: snapshots more than 1.5 s apart are not a pair', () => {
    assert.deepStrictEqual(rows([...BOTS, api(100, 100), api(103, 80, 'hit=1')]), []);
});

test('hp loss, inferred basis: an older build gets the hero flag as fact and the rest as what stood near, marked `?`', () => {
    const [tx, ty] = [TOWERS.find(r => r[0] === 3)[1], TOWERS.find(r => r[0] === 3)[2]];
    // Each case is its own pair ten seconds apart: [x, y of the later snapshot, hit, x of the earlier one if it differs].
    const cases = [
        [[300, -2500, 0], 'creep?'],                    // 300 from their front
        [[300, -2500, 1], 'hero+creep?'],               // and a hero hit
        [[3978 + 700, -5027, 0], 'neutral?'],           // 700 from camp 1's spawn; our own front on the camp must not count
        [[tx + 800, ty, 0], 'tower?'],                  // 800 from an enemy tower
        [[tx + 1400, ty, 0, tx + 800], 'tower?'],       // walked out of reach by the snapshot: the earlier end still counts
        [[0, 9000, 0], 'unexplained'],
    ];
    const lines = [...BOTS];
    cases.forEach(([[x, y, hit, x0]], i) => {
        const t = 100 + 10 * i;
        lines.push(line(t, 'front team=3 top=0.5 topx=9000 topy=9000 mid=0.5 midx=0 midy=-2500 bot=0.5 botx=9000 boty=9000'));
        lines.push(line(t, 'front team=2 top=0.5 topx=3978 topy=-5027 mid=0.5 midx=9000 midy=9000 bot=0.5 botx=9000 boty=9000'));
        lines.push(line(t, `snap pid=1 x=${x0 === undefined ? x : x0} y=${y} alive=1 hp=100 deaths=0 hit=0`));
        lines.push(line(t + 1, `snap pid=1 x=${x} y=${y} alive=1 hp=95 deaths=0 hit=${hit}`));
    });
    assert.deepStrictEqual(rows(lines).map(r => [r.basis, r.src]), cases.map(([, src]) => ['inferred', src]));
});

test('hp loss: a log without `deaths` and a hero without a lineup row still give counted rows and the enemy-side tests', () => {
    const [tx, ty] = [TOWERS.find(r => r[0] === 3)[1], TOWERS.find(r => r[0] === 3)[2]];
    const old = (t, hp) => line(t, `snap pid=1 x=${tx + 100} y=${ty} alive=1 hp=${hp} hit=0`);
    // No ev=bot line: pid 1 is Radiant by its pid, so the Dire tower counts.
    const s = open([old(100, 100), old(101, 95)]);
    const view = s.query('SELECT died, src FROM hp_loss').map(r => [r.died, r.src]);
    const sum = s.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'hp_loss.sql'), 'utf8'), { like: null, from: null, until: null, pid: null })
        .map(r => [r.secs, r.deaths]);
    s.db.close();
    assert.deepStrictEqual([view, sum], [[[0, 'tower?']], [[1, 0]]]);
});

test('hp loss: an allied tower is no source for the inferred basis', () => {
    const [tx, ty] = [TOWERS.find(r => r[0] === 2)[1], TOWERS.find(r => r[0] === 2)[2]];
    const old = (t, hp) => line(t, `snap pid=1 x=${tx + 100} y=${ty} alive=1 hp=${hp} deaths=0 hit=0`);
    assert.deepStrictEqual(rows([...BOTS, old(100, 100), old(101, 95)]).map(r => r.near_tower), [0]);
});

test('@hp_loss sums the view per hero, basis and source inside the window', () => {
    const s = open([...BOTS, api(100, 100), api(101, 95, 'hit=1'), api(102, 88, 'hit=1'), api(103, 85, 'hc=1 ac=1'), api(104, 80, 'hit=1')]);
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'hp_loss.sql'), 'utf8');
    const out = s.query(sql, { like: null, from: null, until: 103, pid: null }).map(r => [r.pid, r.basis, r.src, r.secs, r.loss, r.deaths]);
    s.db.close();
    assert.deepStrictEqual(out, [[1, 'api', 'hero', 2, 12, 0], [1, 'api', 'creep', 1, 3, 0]]);
});

test('hp loss: the tower fragment equals dynamic.js TOWERS', () => {
    const s = new Store(':memory:');
    const frag = fs.readFileSync(path.join(__dirname, '..', 'queries', 'fragments', 'towers.sql'), 'utf8');
    const got = s.query(`WITH ${frag} z(n) AS (VALUES (0)) SELECT team, x, y FROM tw`).map(r => [r.team, r.x, r.y]);
    s.db.close();
    assert.deepStrictEqual(got, TOWERS);
});
