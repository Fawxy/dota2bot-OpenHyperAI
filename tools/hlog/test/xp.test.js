'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { games } = require('../sides');
const { gameResult, rows, LINES } = require('../xp');

const hev = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const RATE = 50 / 60;
// Passive experience as a hero's reading sees it: a whole point at a time.
const base = (k) => Math.floor(RATE * (k + 0.1));
const bump = (k, ...steps) => steps.reduce((a, [from, v]) => a + (k >= from ? v : 0), 0);
// 7.42's level table: 250 to level 2, 400 more to level 3, 550 more to level 4.
const reading = (xp) => (xp < 250 ? `lvl=1 xpn=${250 - xp}` : xp < 650 ? `lvl=2 xpn=${650 - xp}` : `lvl=3 xpn=${1200 - xp}`);
const LAST = 430;

/**
 * Radiant (ours) heroes 1 (pos 1) and 2 (pos 5) at the origin; Dire hero 5 (pos 1) far away, hero 6 (pos 5) at 800.
 * k=10: an enemy melee creep dies beside 1 and 2, who share it (28 each).
 * k=20: an enemy ranged creep is denied by Dire's 5 beside 1 and 2 (half of 69, shared: 17 each).
 * From k=30 hero 2 is far away. k=40: a melee creep, hero 1 alone (57).
 * k=45: hero 6 dies beside hero 1 as another melee creep dies: 177 in one interval.
 * Hero 2, alone and far from everything: +200 at k=50, and +200 at k=425 (after 7:00).
 * Radiant's own creeps: denied by 1 beside hero 6 (k=25); dead at a camp and dead in lane with no Dire hero near (k=35, 36);
 * dead beside hero 6 with no deny (k=37).
 */
function build() {
    const L = [1, 2, 5, 6].map((pid) => hev(-60, `bot pid=${pid} hero=h${pid} team=${pid < 3 ? 2 : 3} pos=${pid === 1 || pid === 5 ? 1 : 5}`));
    L.push(hev(9.6, 'creep_death team=2 kind=melee x=100 y=0 hp=0.1 by=1'));
    L.push(hev(19.6, 'creep_death team=2 kind=ranged x=100 y=0 hp=0.1 by=none'), hev(19.6, 'own_creep_death team=3 kind=ranged x=100 y=0 by=5'));
    L.push(hev(24.6, 'own_creep_death team=2 kind=melee x=100 y=0 by=1'));
    L.push(hev(34.6, 'own_creep_death team=2 kind=melee x=3978 y=-5027 by=none'), hev(35.6, 'own_creep_death team=2 kind=melee x=-3000 y=-500 by=none'));
    L.push(hev(36.6, 'own_creep_death team=2 kind=melee x=100 y=0 by=none'));
    L.push(hev(39.6, 'creep_death team=2 kind=melee x=100 y=0 hp=0.1 by=1'), hev(45.6, 'creep_death team=2 kind=melee x=100 y=0 hp=0.1 by=1'));
    for (let k = 0; k <= LAST; k++) {
        for (const pid of [1, 2, 5, 6]) {
            if (pid === 6 && k > 45 && k < 55) continue;
            let xp = base(k);
            if (pid === 1) xp += bump(k, [10, 28], [20, 17], [40, 57], [46, 177]);
            if (pid === 2) xp += bump(k, [10, 28], [20, 17], [50, 200], [425, 200]);
            const [x, y] = pid === 1 ? [0, 0] : pid === 2 ? (k < 30 ? [0, 0] : [-6000, -6000]) : pid === 5 ? [0, 5000] : [800, 0];
            L.push(hev(k + 0.1, `snap pid=${pid} x=${x} y=${y} alive=1 hp=100 ${reading(xp)} lh=0 dn=0 kills=0 deaths=${pid === 6 && k >= 55 ? 1 : 0} gold=600 nw=600`));
        }
    }
    // The store starts a new game where the clock runs back, so the lines go out in time order.
    const t = (l) => Number(l.match(/t=(-?[\d.]+)/)[1]);
    return L.map((l, i) => [l, i]).sort((x, y) => t(x[0]) - t(y[0]) || x[1] - y[1]).map((x) => x[0]);
}

function ours() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-xp-'));
    const s = new Store(':memory:');
    const f = path.join(dir, '2026-11-24T00-00-00-h2htest_A_rad_1.log');
    fs.writeFileSync(f, build().join('\n') + '\n');
    s.ingest(f);
    const { games: gs } = games(s, ['h2htest']);
    assert.strictEqual(gs.length, 1);
    return gameResult(s, gs[0], LAST + 1);
}

const tick = (k) => base(k) - base(k - 1) - RATE;
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} vs ${b}`);

test('a shared creep, a denied creep and a lone creep land on the hero that gained them, as measured', () => {
    const r = ours();
    // The game's melee value is the median of its three clean readings: twice a shared 28 (two heroes) and the lone 57.
    assert.ok(r.est.melee >= 56 && r.est.melee <= 57.5, `${r.est.melee}`);
    // Hero 1: half of the k=10 creep, the whole k=40 creep, and the k=45 creep at the game's value (a kill shares its interval).
    near(r.pos['ours:1'].parts['lane_creep:melee'], 28 + tick(10) + 57 + tick(40) + r.est.melee);
    near(r.pos['ours:5'].parts['lane_creep:melee'], 28 + tick(10));
    near(r.ours.parts['lane_creep:denied'], 2 * (17 + tick(20)));
    assert.strictEqual(r.oha.lines.lane_creep, 0);
});

test('with a hero death beside it, the creep keeps its value and the rest of the jump is the kill', () => {
    const r = ours();
    near(r.ours.lines.kill, 177 + tick(46) - r.est.melee);
});

test('an unexplained jump is the shrine only at 150 or more after 7:00', () => {
    const r = ours();
    near(r.ours.lines.shrine, 200 + tick(425));
    near(r.ours.parts['other:100+'], 200 + tick(50));
});

test('the lines sum exactly to the experience gained, per side, and the memo rows stay out of the sum', () => {
    const r = ours();
    for (const side of ['ours', 'oha']) {
        const sum = LINES.reduce((a, l) => a + r[side].lines[l], 0);
        near(sum, r[side].xpChange);
    }
    assert.strictEqual(r.ours.xpChange, 2 * (base(LAST) - base(0)) + 2 * 28 + 2 * 17 + 57 + 177 + 400);
    const rs = rows({ games: [r] });
    near(rs.find((x) => x.row === 'sum_of_lines').ours, rs.find((x) => x.row === 'xp_change').ours);
    assert.ok(rs.findIndex((x) => x.row === 'kept_from_them') > rs.findIndex((x) => x.row === 'sum_of_lines'));
});

test('kept from them: half of our deny in their reach, all of a creep that died out of it, nothing for one they stood by', () => {
    const r = ours();
    near(r.ours.parts['kept_from_them:deny'], r.est.melee / 2);
    near(r.ours.parts['kept_from_them:out_of_range_camp'], r.est.melee);
    near(r.ours.parts['kept_from_them:out_of_range_lane'], r.est.melee);
    // Dire's deny of its ranged creep beside our two: half of 69 (the reference value; two samples are too few for the game's own).
    assert.strictEqual(r.oha.parts['kept_from_them:deny'], 34.5);
    const rs = rows({ games: [r] });
    near(rs.find((x) => x.row === 'kept_from_them').ours, 2.5 * r.est.melee);
});
