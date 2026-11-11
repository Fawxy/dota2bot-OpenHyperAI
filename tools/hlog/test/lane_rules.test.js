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

test('D1: a hero that runs with the chasers at its heels left; the nearest-enemy distance alone does not decide', () => {
    const lines = bots([[1, 2, 1], [6, 3, 1], [7, 3, 2]]);
    for (let t = 100; t <= 110; t++) {
        const x = PX - 250 * (t - 100);
        lines.push(snap(t, 1, x, PY, { hit: 1, hp: 45, mode: 'retreat' }));
        lines.push(snap(t, 6, x + 300, PY), snap(t, 7, x + 300, PY + 100));
    }
    assert.deepStrictEqual(cases(lines, 'D1'), [[1, 100, 0, 'left']]);
});

test('deaths: dated at the last snapshot alive before the fountain ghost, and a death with no respawn before the end counts', () => {
    const lines = bots([[1, 2, 1], [2, 2, 2], [6, 3, 1], [7, 3, 2]]);
    for (let t = 100; t <= 104; t++) {
        lines.push(snap(t, 1, PX, PY, { hit: 1, hp: 40 - 8 * (t - 100) }));
        lines.push(snap(t, 6, PX + 300, PY), snap(t, 7, PX + 300, PY + 100));
    }
    // Killed at 104: two HP-0 snapshots where it fell, then (4 s after the last alive one) two at the fountain, HP rising.
    lines.push(snap(105, 1, PX, PY, { hp: 0 }), snap(106, 1, PX, PY, { hp: 0 }));
    lines.push(snap(108, 1, -6650, -6650, { hp: 1 }), snap(109, 1, -6650, -6650, { hp: 2 }));
    for (let t = 150; t <= 700; t++) lines.push(snap(t, 1, -6700, -6700, { deaths: 1 }));
    // Pid 2 dies at 600 and the game ends at 700 before its respawn.
    for (let t = 105; t <= 700; t++) {
        if (t <= 600) lines.push(snap(t, 2, -4000, -4000));
        lines.push(snap(t, 6, 4000, 4000), snap(t, 7, 4000, 4100));
    }
    const s = new Store(':memory:');
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lrules-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    s.ingest(f);
    s.refreshViews();
    const rows = s.query(`WITH gm AS MATERIALIZED (SELECT +game_id AS game_id, file FROM games),
-- include: lane_rules
x AS (SELECT 1) SELECT pid, dsec FROM lr_death ORDER BY pid`, {});
    s.db.close();
    assert.deepStrictEqual(rows.map(r => [r.pid, r.dsec]), [[1, 104], [2, 600]]);
    assert.deepStrictEqual(run('rule_counts', lines).map(r => [r.team, r.d1_v, r.deaths]), [[2, 1, 2], [3, 0, 0]]);
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

test('D24: leaving an even fight at high HP inside our creep aggro violates; outnumbered, at low HP, nobody in reach or hit for free does not', () => {
    const lines = bots([[1, 2, 1], [2, 2, 5], [6, 3, 3], [7, 3, 4]]);
    const front = (t, x, y) => line(t, `front team=2 top=0.5 topx=${x} topy=${y} mid=0.5 midx=0 midy=0 bot=0.5 botx=5000 boty=-6000`);
    for (let t = 190; t <= 620; t++) {
        // 200-203: the partner beside us, two enemies in reach (2v2), 90% HP, our lane front beside them. 300: the partner
        // 3,000 away (1v2). 400: 2v2 at 40% HP. 500: nobody within 1,500 (D2's case, not this one). 600: the 2v2 at 90% with
        // our front 1,500 behind us: they hit for free and stepping out is right.
        const at = [200, 300, 400, 500, 600].find(s => t >= s && t <= s + 3);
        const mode = at !== undefined ? 'retreat' : 'laning';
        const hp = at === 400 ? 40 : 90;
        const far = at === 500 ? 4000 : 400;
        lines.push(snap(t, 1, PX, PY, { mode, hp }), snap(t, 2, at === 300 ? PX - 3000 : PX - 200, PY));
        lines.push(snap(t, 6, PX + far, PY), snap(t, 7, PX + far, PY + 100));
        lines.push(at === 600 ? front(t, PX - 1500, PY) : front(t, PX + 300, PY));
    }
    const out = run('rule_cases', lines, { rule: 'D24', all: 1 }).map(r => [r.pid, r.t, r.viol, r.cause]);
    assert.deepStrictEqual(out, [[1, 200, 1, 'ours_retreat'], [1, 600, 0, 'free_hit']]);
});

test('D24h: hit by a hero standing in our creep aggro, a hero that never attacks an enemy hero violates; a hit back, a leave, a free hit or low HP does not', () => {
    const lines = bots([[1, 2, 1], [6, 3, 3]]);
    const front = (t, x) => line(t, `front team=2 top=0.5 topx=${x} topy=${PY} mid=0.5 midx=0 midy=0 bot=0.5 botx=5000 boty=-6000`);
    const tgtSnap = (t, o, tgt) => snap(t, 1, PX, PY, o).replace(/$/, tgt ? ` tgt=${tgt}` : '');
    for (let t = 190; t <= 720; t++) {
        // 200: hit, the hitter beside our front, no attack back (none). 300: hit, and at 302 our target is the enemy hero
        // (hit_back). 400: hit, then retreat mode at 401 (left). 500: hit with our front 1,500 away (a free hit: not this
        // rule). 600: hit at 40% HP (not this rule). 610: 2 s after 600 and still hit: no new onset inside 5 s of the last.
        const at = [200, 300, 400, 500, 600].find(s => t >= s && t <= s + 3);
        const hit = at !== undefined || (t >= 604 && t <= 612) ? 1 : 0;
        const hp = t >= 600 && t <= 612 ? 40 : 90;
        const mode = at === 400 && t > 400 ? 'retreat' : 'laning';
        const tgt = at === 300 && t === 302 ? 'npc_dota_hero_h6' : t === 202 ? 'npc_dota_creep_goodguys_melee' : undefined;
        lines.push(tgtSnap(t, { hit, hp, mode }, tgt), snap(t, 6, PX + 400, PY));
        lines.push(front(t, at === 500 ? PX - 1500 : PX + 300));
    }
    assert.deepStrictEqual(cases(lines, 'D24h'), [[1, 200, 1, 'none'], [1, 300, 0, 'hit_back'], [1, 400, 0, 'left']]);
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

test('D3: walking on counts only while our own lane front is nearer than our fountain', () => {
    // Radiant pos1 (bot lane), front at (5000, -6000), chased to 102 or 202, then 13 s at 90% HP with nobody near.
    const lines = bots([[1, 2, 1], [6, 3, 1]]);
    const walk = (t0, x, y) => {
        for (let t = t0; t <= t0 + 15; t++) {
            lines.push(snap(t, 1, x - 50 * (t - t0), y, { mode: 'retreat', hp: 90 }));
            lines.push(snap(t, 6, t <= t0 + 2 ? x + 800 : x + 6000, y + 4000));
            lines.push(line(t, 'front team=2 top=0.5 topx=-6300 topy=2000 mid=0.5 midx=-1500 midy=-1300 bot=0.5 botx=5000 boty=-6000'));
        }
    };
    walk(100, 3000, -5500); // 2,000 from the front, 9,800 from the fountain: no_stop
    walk(200, -4500, -5000); // 2,800 from the fountain, 9,500 from the front: walking home is right
    assert.deepStrictEqual(cases(lines, 'D3'), [[1, 100, 1, 'no_stop'], [1, 200, 0, 'ok']]);
});

test('D3: a Dire pos3 reads the bot lane front (Dire offlane), not its top or mid', () => {
    // Dire fountain (6928, 6372). Bot front (6000, -1000) is 2,000 from the walk at (6000, 1000), the fountain 5,400; top and
    // mid fronts are farther than the fountain, so only the bot lane makes the walk-on count.
    const lines = bots([[1, 2, 1], [6, 3, 3]]);
    for (let t = 100; t <= 115; t++) {
        lines.push(snap(t, 6, 6000, 1000 + 50 * (t - 100), { mode: 'retreat', hp: 90 }));
        lines.push(snap(t, 1, t <= 102 ? 6000 : 0, t <= 102 ? 200 : -4000));
        lines.push(line(t, 'front team=3 top=0.5 topx=-6000 topy=6000 mid=0.5 midx=-1000 midy=-1000 bot=0.5 botx=6000 boty=-1000'));
    }
    assert.deepStrictEqual(cases(lines, 'D3').filter(c => c[0] === 6), [[6, 100, 1, 'no_stop']]);
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

test('D7: a dip back under 2,000 is one departure, a respawn is none, and a support fleeing for its life is self', () => {
    const lines = bots([[0, 2, 1], [3, 2, 5], [5, 3, 3], [6, 3, 4]]);
    // 300-305 together, then 2,100, 1,900, 2,100 away: one departure at 306.
    // 400-405 together, dead 406-410, back at 411 far away: no departure (no snapshot the second before).
    // 500-505 together, then 2,100 away in retreat mode with the core at 60%: self.
    const sx = { 306: 2100, 307: 1900, 308: 2100, 309: 2100, 411: 2500, 412: 2500, 506: 2100, 507: 2100 };
    for (let t = 300; t <= 510; t++) {
        if (t > 310 && t < 400 || t > 412 && t < 500) continue;
        lines.push(snap(t, 0, PX, PY, { hp: t >= 500 ? 60 : 100 }));
        lines.push(snap(t, 5, PX + 800, PY), snap(t, 6, PX + 800, PY + 100));
        if (t >= 406 && t <= 410) continue;
        lines.push(snap(t, 3, PX - (sx[t] || 100), PY, { mode: t >= 506 ? 'retreat' : 'laning', deaths: t >= 411 && t < 500 ? 1 : t >= 500 ? 1 : 0 }));
    }
    assert.deepStrictEqual(cases(lines, 'D7'), [[3, 306, 0, 'free'], [3, 506, 0, 'self']]);
});

test('D9: a trip out of lane where two enemies reach the hero alone violates; a quiet one does not', () => {
    const lines = bots([[4, 2, 4], [5, 3, 3], [6, 3, 4]]);
    // 300-305 exposed, 400-405 quiet, 500-505 a flight that starts in retreat mode (D1's, not a trip).
    for (let t = 295; t <= 510; t++) {
        const off = (t >= 300 && t <= 305) || (t >= 400 && t <= 405) || (t >= 500 && t <= 505);
        lines.push(snap(t, 4, PX, PY, { ld: off ? 2000 : 0, mode: t >= 500 ? 'retreat' : 'laning' }));
        const near = t <= 305 || t >= 500;
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
