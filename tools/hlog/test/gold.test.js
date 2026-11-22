'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { games, gameResult, parseLabel, rows, LINES } = require('../gold');

const hev = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
// The baseline passive income as a hero's nw sees it: a whole gold at a time, 1.46 a second on average.
const base = (k) => 600 + Math.floor(1.46 * k);
const bump = (k, ...steps) => steps.reduce((a, [from, v]) => a + (k >= from ? v : 0), 0);

/**
 * Radiant (ours, the `_rad_` seat) heroes 1 (pos 1) and 2; Dire heroes 5 and 6. Snapshots at k + 0.1 s for k = 0..60.
 * Hero 1: a melee last hit worth 40 at k=10, a tango charge eaten (-30) at k=20, a ranged last hit worth 30 at k=30.
 * Hero 5 dies after k=40: no snapshots until k=50, and its nw is 25 lower for it.
 */
function build() {
    const L = [1, 2, 5, 6].map((pid) => hev(-60, `bot pid=${pid} hero=h${pid} team=${pid < 3 ? 2 : 3} pos=${pid === 1 || pid === 5 ? 1 : 5}`));
    L.push(hev(0.1, 'inv pid=1 items="s0=tango:3 s15=tpscroll:1"'), hev(19.6, 'inv pid=1 items="s0=tango:2 s15=tpscroll:1"'));
    L.push(hev(9.6, 'creep_death team=2 kind=melee x=0 y=0 hp=0.1 by=1'), hev(29.6, 'creep_death team=2 kind=ranged x=0 y=0 hp=0.1 by=1'));
    for (let k = 0; k <= 60; k++) {
        const t = k + 0.1;
        for (const pid of [1, 2, 5, 6]) {
            if (pid === 5 && k > 40 && k < 50) continue;
            let nw = base(k);
            let lh = 0;
            if (pid === 1) { nw += bump(k, [10, 40], [20, -30], [30, 30]); lh = (k >= 10) + (k >= 30); }
            if (pid === 5) nw += bump(k, [50, -25]);
            const x = pid < 3 ? -5000 : 5000;
            L.push(hev(t, `snap pid=${pid} x=${x} y=0 alive=1 hp=100 lvl=1 lh=${lh} dn=0 kills=0 deaths=${pid === 5 && k >= 50 ? 1 : 0} gold=${nw - 560} nw=${nw}`));
        }
    }
    return L;
}

function ours() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-gold-'));
    const s = new Store(':memory:');
    const f = path.join(dir, '2026-11-22T00-00-00-h2htest_A_rad_1.log');
    fs.writeFileSync(f, build().join('\n') + '\n');
    s.ingest(f);
    const { games: gs } = games(s, ['h2htest']);
    assert.strictEqual(gs.length, 1);
    return gameResult(s, gs[0], 60);
}

test('each source lands on its own line, with the passive tick taken out of the interval it shares', () => {
    const r = ours();
    const d = (a, b) => base(b) - base(a);
    assert.ok(Math.abs(r.ours.parts['lane_creep:melee'] - (40 + d(9, 10) - 1.46)) < 1e-9);
    assert.ok(Math.abs(r.ours.parts['lane_creep:ranged'] - (30 + d(29, 30) - 1.46)) < 1e-9);
    // The loss takes the interval's whole fall past the passive tick, 1.46 of its two-gold step, so it is 30 less that rounding.
    assert.ok(Math.abs(r.ours.parts['consumable:tango'] - (d(19, 20) - 30 - 1.46)) < 1e-9);
    // Hero 5's whole dead gap is one interval: passive for all ten seconds, the rest of the fall is the death.
    assert.ok(Math.abs(r.oha.lines.death - (d(40, 50) - 25 - 1.46 * 10)) < 1e-9);
    assert.strictEqual(r.ours.lines.other_income, 0);
    assert.strictEqual(r.ours.lines.other_loss, 0);
});

test('the lines sum exactly to the net-worth change, per side and per hero', () => {
    const r = ours();
    for (const side of ['ours', 'oha']) {
        const sum = LINES.reduce((a, l) => a + r[side].lines[l], 0);
        assert.ok(Math.abs(sum - r[side].nwChange) < 1e-9, `${side}: ${sum} vs ${r[side].nwChange}`);
    }
    assert.ok(Math.abs(r.pos['ours:1'].lines.lane_creep - (r.ours.lines.lane_creep)) < 1e-9);
    const rs = rows({ games: [r] });
    assert.ok(Math.abs(rs.find((x) => x.row === 'sum_of_lines').ours - rs.find((x) => x.row === 'nw_change').ours) < 1e-9);
});

test('batch arm labels join the arm and the seat with a hyphen, Dire as dir', () => {
    assert.deepStrictEqual(parseLabel('h2hlift1_B_off-dir_10'), { run: 'h2hlift1', lineup: 'B', arm: 'off', seat: 3, n: 10 });
    assert.deepStrictEqual(parseLabel('h2hlift1_A_off-rad_1'), { run: 'h2hlift1', lineup: 'A', arm: 'off', seat: 2, n: 1 });
    assert.deepStrictEqual(parseLabel('h2hlift1_A_owncorenolift-dir_3'), { run: 'h2hlift1', lineup: 'A', arm: 'owncorenolift', seat: 3, n: 3 });
});

test('bisect labels carry the arm with the seat glued on', () => {
    assert.deepStrictEqual(parseLabel('bis1r_C_noTdire_1'), { run: 'bis1r', lineup: 'C', arm: 'noT', seat: 3, n: 1 });
    assert.deepStrictEqual(parseLabel('bis1_B_BFrad_2'), { run: 'bis1', lineup: 'B', arm: 'BF', seat: 2, n: 2 });
    assert.deepStrictEqual(parseLabel('h2h742_A_dire_3'), { run: 'h2h742', lineup: 'A', arm: '', seat: 3, n: 3 });
});

test('a label with no seat is a mirror game: Radiant stands for ours, and the label says so', () => {
    assert.deepStrictEqual(parseLabel('stockbase2_A_stock_7'), { run: 'stockbase2', lineup: 'A', arm: 'stock', seat: 2, n: 7, mirror: true });
    assert.deepStrictEqual(parseLabel('stockbase2_C_off_9'), { run: 'stockbase2', lineup: 'C', arm: 'off', seat: 2, n: 9, mirror: true });
    assert.strictEqual(parseLabel('h2h742_A_rad_3').mirror, undefined);
    assert.strictEqual(parseLabel('stock-events_smoke'), undefined);
});

test('a mirror game is read, not skipped, and gives the same totals as the same log under a Radiant seat', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-gold-'));
    const s = new Store(':memory:');
    for (const name of ['2026-11-22T00-00-00-mirtest_A_stock_1.log', '2026-11-22T00-00-01-radtest_A_rad_1.log']) {
        const f = path.join(dir, name);
        fs.writeFileSync(f, build().join('\n') + '\n');
        s.ingest(f);
    }
    const m = games(s, ['mirtest']);
    assert.strictEqual(m.skipped.length, 0);
    assert.strictEqual(m.games.length, 1);
    assert.strictEqual(m.games[0].mirror, true);
    const r = games(s, ['radtest']).games[0];
    const a = gameResult(s, m.games[0], 60);
    const b = gameResult(s, r, 60);
    assert.deepStrictEqual(a.ours.lines, b.ours.lines);
    assert.deepStrictEqual(a.oha.lines, b.oha.lines);
});
