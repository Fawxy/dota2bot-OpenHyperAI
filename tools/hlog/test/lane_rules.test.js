'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { TOWERS } = require('../dynamic');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const query = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

// Away from every tower and fountain, so only the heroes decide.
const PX = -2000, PY = 3000;

/** Ours on Radiant (team 2), OHA on Dire (team 3), as a head-to-head game logs them. */
function bots(heroes) {
    return heroes.map(([pid, team, pos]) => line(0, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos} ours=Threat:${team === 2 ? 1 : 0}`));
}

const snap = (t, pid, x, y, o = {}) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${o.hp ?? 100} mode=${o.mode ?? 'laning'} ` +
    `lvl=${o.lvl ?? 3} deaths=${o.deaths ?? 0} ar=${o.ar ?? 550} ld=${o.ld ?? 0} hit=${o.hit ?? 0}`);

function run(name, lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lrules-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(query(name), params);
    s.db.close();
    return out;
}

const cases = (lines, rule) => run('rule_cases', lines, { rule, all: 1 }).map(r => [r.pid, r.t, r.viol, r.cause]);

test('D1: outnumbered and hit, a hero that stays or dies violates; one that walks away does not', () => {
    const game = move => {
        const lines = bots([[1, 2, 1], [6, 3, 1], [7, 3, 2]]);
        for (let t = 100; t <= 110; t++) {
            const p = move(t);
            if (p) lines.push(snap(t, 1, p[0], PY, { hit: t === 100 ? 1 : 0, hp: 70 }));
            lines.push(snap(t, 6, PX + 300, PY), snap(t, 7, PX + 300, PY + 100));
        }
        return lines;
    };
    assert.deepStrictEqual(cases(game(() => [PX]), 'D1'), [[1, 100, 1, 'stayed']]);
    assert.deepStrictEqual(cases(game(t => [PX - 350 * (t - 100)]), 'D1'), [[1, 100, 0, 'left']]);
    // Killed at 104: no snapshot while dead, the counter rises at the respawn.
    const died = game(t => (t <= 104 ? [PX] : null));
    died.push(snap(140, 1, -6700, -6700, { deaths: 1 }));
    assert.deepStrictEqual(cases(died, 'D1'), [[1, 100, 1, 'died']]);
});

test('D1: two enemies against me and an ally near is no situation', () => {
    const lines = bots([[1, 2, 1], [2, 2, 5], [6, 3, 1], [7, 3, 2]]);
    for (let t = 100; t <= 105; t++) {
        lines.push(snap(t, 1, PX, PY, { hit: 1, hp: 40 }), snap(t, 2, PX - 200, PY));
        lines.push(snap(t, 6, PX + 300, PY), snap(t, 7, PX + 300, PY + 100));
    }
    assert.deepStrictEqual(cases(lines, 'D1'), []);
});

test('D2: a retreat at high HP with no enemy near is a violation; a 1 s flicker and a low-HP retreat are not', () => {
    const lines = bots([[1, 2, 1], [6, 3, 1]]);
    for (let t = 200; t <= 320; t++) {
        const mode = (t >= 200 && t <= 203) || t === 250 || (t >= 300 && t <= 303) ? 'retreat' : 'laning';
        lines.push(snap(t, 1, PX, PY, { mode, hp: t >= 300 ? 60 : 100 }), snap(t, 6, PX + 3000, PY));
    }
    const out = run('rule_cases', lines, { rule: 'D2', all: 1 }).map(r => [r.pid, r.t, r.secs, r.cause]);
    assert.deepStrictEqual(out, [[1, 200, 4, 'ours_retreat']]);
});

test('D3: a retreat that walks on after the threat ends, or into an enemy tower, violates; a short one does not', () => {
    const lines = bots([[1, 2, 1], [6, 3, 1]]);
    // 400-415: chased to 402, then 13 s more at 90% HP with nobody near: no_stop.
    for (let t = 400; t <= 415; t++) {
        lines.push(snap(t, 1, PX - 300 * (t - 400), PY, { mode: 'retreat', hp: 90 }));
        lines.push(snap(t, 6, t <= 402 ? PX - 300 * (t - 400) + 800 : PX + 4000, PY));
    }
    // 500-503: walks from 2,000 to 500 short of the Dire tower at (524, 652), the enemy at its heels: tower.
    for (let t = 500; t <= 503; t++) {
        const y = 652 - 2000 + 500 * (t - 500);
        lines.push(snap(t, 1, 524, y, { mode: 'retreat', hp: 90 }), snap(t, 6, 524, y - 800));
    }
    // 600-605: leaves while the enemy is near, stops: ok.
    for (let t = 600; t <= 605; t++) {
        lines.push(snap(t, 1, PX, PY, { mode: t <= 603 ? 'retreat' : 'laning', hp: 90 }), snap(t, 6, PX + 800, PY));
    }
    assert.deepStrictEqual(cases(lines, 'D3'), [[1, 400, 1, 'no_stop'], [1, 500, 1, 'tower'], [1, 600, 0, 'ok']]);
});

test('D7: a support leaving its core in a 1v2 at low HP violates; leaving a healthy core does not', () => {
    const lines = bots([[0, 2, 1], [3, 2, 5], [5, 3, 3], [6, 3, 4]]);
    for (const [t0, hp] of [[100, 60], [200, 100]]) {
        for (let t = t0; t <= t0 + 10; t++) {
            lines.push(snap(t, 0, PX, PY, { hp }), snap(t, 3, t <= t0 + 5 ? PX + 100 : PX - 2100, PY));
            lines.push(snap(t, 5, PX + 800, PY), snap(t, 6, PX + 800, PY + 100));
        }
    }
    assert.deepStrictEqual(cases(lines, 'D7'), [[3, 106, 1, 'needed'], [3, 206, 0, 'free']]);
});

test('D9: a trip out of lane where two enemies reach the hero alone violates; a quiet one does not', () => {
    const lines = bots([[4, 2, 4], [5, 3, 3], [6, 3, 4]]);
    for (let t = 300; t <= 410; t++) {
        const off = (t >= 300 && t <= 305) || (t >= 400 && t <= 405);
        lines.push(snap(t, 4, PX, PY, { ld: off ? 2000 : 0 }));
        const near = t <= 305;
        lines.push(snap(t, 5, near ? PX + 300 : PX + 4000, PY), snap(t, 6, near ? PX + 300 : PX + 4000, PY + 100));
    }
    assert.deepStrictEqual(cases(lines, 'D9'), [[4, 300, 1, 'exposed'], [4, 400, 0, 'safe']]);
});

test('rule counts: per side, situations, violations and deaths', () => {
    const lines = bots([[1, 2, 1], [6, 3, 1], [7, 3, 2]]);
    for (let t = 100; t <= 104; t++) {
        lines.push(snap(t, 1, PX, PY, { hit: 1, hp: 40 }));
        lines.push(snap(t, 6, PX + 300, PY), snap(t, 7, PX + 300, PY + 100));
    }
    lines.push(snap(140, 1, -6700, -6700, { deaths: 1 }));
    for (let t = 105; t <= 140; t++) lines.push(snap(t, 6, PX + 300, PY), snap(t, 7, PX + 300, PY + 100));
    const out = run('rule_counts', lines).map(r => [r.side, r.team, r.d1_n, r.d1_v, r.deaths]);
    assert.deepStrictEqual(out, [['ours', 2, 1, 1, 1], ['oha', 3, 0, 0, 0]]);
});

test('lane rules: the tower table equals dynamic.js TOWERS', () => {
    const values = query('fragments/lane_rules').match(/lr_tw \(team, x, y\) AS \(VALUES([\s\S]*?\))\),/)[1];
    const rows = [...values.matchAll(/\((\d), (-?\d+), (-?\d+)\)/g)].map(m => m.slice(1).map(Number));
    assert.deepStrictEqual(rows, TOWERS);
});
