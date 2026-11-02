'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { coreLane, economy } = require('../nf');

// Radiant safe lane (bot) near its T1, as in lasthit_cause.test.js; the Dire pos1 stands in the same lane (its own safe lane is
// top, but only distance to the death counts here).
const BOT = [-360, -6256];
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

/** Radiant pos1 pid 1 (2 of 4 near deaths its own), Dire pos1 pid 6 (1 of 2), each with snaps and lane_pos; `extra` lines. */
function log(extra = []) {
    const out = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=1')];
    for (let t = 1; t <= 650; t += 10) {
        out.push(line(t, `snap pid=1 x=${BOT[0]} y=${BOT[1]} alive=1 lh=0 dn=${t < 600 ? 4 : 9} lvl=${t < 600 ? 5 : 7} deaths=1`));
        out.push(line(t, `snap pid=6 x=${BOT[0]} y=${BOT[1]} alive=1 lh=0 dn=2 lvl=4 deaths=0`));
        out.push(line(t + 0.5, `lane_pos pid=1 owned=1 running=1 mode=1 spot=oha hph=${t < 600 ? 300 : 999}`));
        out.push(line(t + 0.5, `lane_pos pid=6 owned=1 running=1 mode=1 spot=oha hph=100`));
    }
    const near = 'p1d=100 p1r=150 p1t=0';
    out.push(line(100, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=1 ${near}`));
    out.push(line(130, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=1 ${near}`));
    out.push(line(160, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=none ${near}`));
    out.push(line(190, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=none ${near}`));
    // Past 10:00: not counted.
    out.push(line(610, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=1 ${near}`));
    // Far from the core (p1d over 1000): not in the denominator.
    out.push(line(220, `creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=none p1d=1500 p1r=150 p1t=0`));
    out.push(line(250, `creep_death team=3 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=6 ${near}`));
    out.push(line(280, `creep_death team=3 kind=melee x=${BOT[0]} y=${BOT[1] + 100} hp=0.1 by=none ${near}`));
    out.push(...extra);
    return out.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n');
}

function run(text) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-core-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = coreLane(s, f, 1);
    s.db.close();
    return out;
}

test('conversion per team and the mean of the two teams, near deaths before 10:00 only', () => {
    const o = run(log());
    assert.strictEqual(o.conv_lpos1_r, 0.5);
    assert.strictEqual(o.conv_lpos1_d, 0.5);
    assert.strictEqual(o.conv_lpos1, 0.5);
});

test('costs are read at or before 10:00, not at the end of the log', () => {
    const o = run(log());
    assert.strictEqual(o.dn_at_10_lpos1, (4 + 2) / 2);
    assert.strictEqual(o.lvl_at_10_lpos1, (5 + 4) / 2);
    assert.strictEqual(o.hph_at_10_lpos1, (300 + 100) / 2);
});

test('a position one team lacks leaves the mean undefined, never half of one team', () => {
    const o = run(log());
    assert.strictEqual(o.conv_lpos2, undefined);
    assert.strictEqual(o.dn_at_10_lpos2, undefined);
    // A Dire pos2 with snaps but no near deaths: its conversion is undefined, so the pos2 mean stays undefined.
    const o2 = run(log([line(0, 'bot pid=2 hero=h2 team=2 pos=2'), line(5, `snap pid=2 x=0 y=0 alive=1 lh=0 dn=1 lvl=3 deaths=0`)]));
    assert.strictEqual(o2.conv_lpos2_r, undefined);
    assert.strictEqual(o2.conv_lpos2, undefined);
});

function runEconomy(text) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-econ-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = economy(s, f, 1);
    s.db.close();
    return out;
}

test('economy: per-team guard counts at 10:00, share undefined without own-side rows', () => {
    const o = runEconomy(log());
    // pid 1 (Radiant) dn=4 lh=0 at t<600; pid 6 (Dire) dn=2.
    assert.strictEqual(o.team_lhdn_r, 4);
    assert.strictEqual(o.team_lhdn_d, 2);
    assert.strictEqual(o.core_dn_r, 4);
    // deaths=1 in the snaps, +1: the last snap at 590 s is over 2.5 s before 10:00 (creep_guard counts the hero as still dead).
    assert.strictEqual(o.deaths_t_r, 2);
    assert.strictEqual(o.share_r, undefined);
});

test('economy: share and not_in_share are numbers once the team logs own-side creep deaths', () => {
    const own = [line(120, `own_creep_death team=2 kind=melee x=${BOT[0]} y=${BOT[1]} hp=0.1 by=1`)];
    const o = runEconomy(log(own));
    assert.strictEqual(typeof o.share_r, 'number');
    assert.ok(o.share_r >= 0 && o.share_r <= 1);
    assert.strictEqual(typeof o.not_in_share_r, 'number');
});
