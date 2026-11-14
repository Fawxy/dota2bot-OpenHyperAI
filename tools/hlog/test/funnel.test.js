'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { ledger, split } = require('../ledger');
const { run } = require('../funnel');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
// Radiant (ours, the `_rad_` seat) pos 2 pid 1 and pos 5 pid 2 against Dire pos 2 pid 5 and pos 5 pid 6.
const BOTS = [[1, 2, 2], [2, 2, 5], [5, 3, 2], [6, 3, 5]].map(([pid, team, pos]) => line(-60, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos}`));
const snap = (t, pid, x, y, o = {}) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${o.hp ?? 100} lh=0 deaths=${o.d ?? 0}`
    + ` mode=${o.mode ?? 'laning'} ln=${o.ln ?? 'mid'} ld=100 hit=${o.hit ?? 0} ah=${o.ah ?? 0} at=0 ac=0 an=0 hc=0`);
// A hero record of a cut: pid, x, y, hp, range, hull, speed, attacking, engaged, damage over 3 s, over 6 s, illusion.
const hero = (o = {}) => `6,300,0,500,550,24,300,0,${o.eng ?? 0},${o.e3 ?? 100},${o.e6 ?? 200},0`;

function store(logs) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-funnel-'));
    const s = new Store(':memory:');
    for (const [name, lines] of Object.entries(logs)) {
        const f = path.join(dir, `2026-11-13T00-00-00-${name}.log`);
        // Lines in time order (stable), as the game writes them: a clock that runs back reads as a new game.
        const at = (l) => Number(/t=(\S+)/.exec(l)[1]);
        fs.writeFileSync(f, [...BOTS, ...[...lines].sort((a, b) => at(a) - at(b))].join('\n') + '\n');
        s.ingest(f);
    }
    s.refreshViews();
    return s;
}

/** Our mid (pid 1) stands at the centre in laning mode; Dire's mid at the same place. Denies at 1,000 and 1,500 from it, at `t`s. */
function denies(deniesAt, o = {}) {
    const lines = [];
    for (let t = 60; t <= 130; t++) {
        lines.push(snap(t, 1, 0, 0, { hp: o.hp ?? 100, mode: o.mode }), snap(t, 5, 0, 0));
        lines.push(line(t, `lane_pos pid=1 owned=1 running=1 rp=${o.rp ?? 'burst'} why=pref`));
    }
    for (const t of deniesAt) {
        lines.push(line(t, `creep_death team=2 kind=melee x=1000 y=1000 hp=10 by=deny p2d=1000 p2r=150 p2t=0`));
        lines.push(line(t - 1, `cut pid=1 kind=spot role=core lane=2 b=0,0,500,600,150,24,300,0 he=${o.he ?? hero()}`));
    }
    return lines;
}

const steps = (r) => Object.fromEntries(r.result.steps.map((s) => [s.label, [s.ours, s.oha]]));

test('the creep funnel narrows from the cause to the burst band, and keeps OHA only where its telemetry exists', () => {
    const s = store({ den_A_rad_1: denies([100, 110]) });
    const r = run(s, { runs: ['den'], cause: 'denied', lane: 'mid', minDist: 800, until: 720, at: 600 });
    const st = steps(r);
    assert.deepStrictEqual(st['denied in mid'], [2, 0]);
    assert.deepStrictEqual(st['core over 800 away'], [2, 0]);
    assert.deepStrictEqual(st['core in laning mode'], [2, 0]);
    assert.deepStrictEqual(st['held by burst'], [2, null]);
    assert.deepStrictEqual(st['HP 50% or more'], [2, null]);
    assert.deepStrictEqual(st['none is hitting'], [2, null]);
    assert.deepStrictEqual(st['burst under 1'], [2, null]);
    const bands = r.result.steps.find((x) => x.label === 'burst over HP').parts;
    assert.deepStrictEqual(bands.map((b) => [b.label, b.ours]), [['under 0.35', 2], ['0.35 to 0.5', 0], ['0.5 to 1', 0], ['1 or more', 0]]);
});

test('the funnel drops a core not in laning mode, one under half HP, and a hitting hero or a burst of 1 or more falls out of its step', () => {
    const none = (o) => run(store({ x_A_rad_1: denies([100], o) }), { runs: ['x'], cause: 'denied', lane: 'mid', until: 720, at: 600 });
    assert.strictEqual(steps(none({ mode: 'retreat' }))['core in laning mode'][0], 0);
    assert.strictEqual(steps(none({ hp: 40 }))['HP 50% or more'][0], 0);
    const hit = none({ he: hero({ eng: 1 }) });
    assert.deepStrictEqual([steps(hit)['1 enemy hero in the spot cut'][0], steps(hit)['none is hitting'][0]], [1, 0]);
    const big = none({ he: hero({ e3: 600 }) });
    assert.deepStrictEqual([steps(big)['none is hitting'][0], steps(big)['burst under 1'][0]], [1, 0]);
    assert.strictEqual(steps(none({ rp: 'none' }))['held by burst'][0], 0);
});

test('--split cuts the cause by distance, and a distance filter leaves the dist split whole', () => {
    const s = store({ den_A_rad_1: denies([100, 110]) });
    const r = run(s, { runs: ['den'], cause: 'denied', lane: 'mid', split: 'dist', minDist: 2000, until: 720, at: 600 });
    assert.deepStrictEqual(r.result.parts.filter((p) => p.ours).map((p) => [p.label, p.ours]), [['800-1500', 2]]);
});

test('the deaths funnel counts the position\'s deaths by cause for both sides, and for ours the retreat, the stay and the first hit', () => {
    const lines = [];
    for (let t = 80; t <= 100; t++) {
        const hit = t >= 92 ? 1 : 0;
        lines.push(snap(t, 1, 0, 0, { hp: Math.max(5, 100 - 5 * (t - 80)), hit, ah: hit, mode: 'laning' }));
        lines.push(snap(t, 5, 300, 0));
    }
    lines.push(snap(130, 1, -6850, -6461, { d: 1 }));
    lines.push(line(90, 'cut pid=1 kind=leave dec=hold b=0,0,500,600,150,24,300,0 he=""'));
    lines.push(line(85, 'retreat pid=1 ph=start kind=ours ep=1 why=threat'));
    const r = run(store({ die_A_rad_1: lines }), { runs: ['die'], deaths: true, pos: '2', until: 720, at: 600 });
    assert.deepStrictEqual(r.result.causes.map((c) => [c.label, c.ours, c.oha]), [['duel', 1, 0], ['total', 1, 0]]);
    const by = Object.fromEntries(r.result.ours.map((g) => [g.label, g.parts.filter((p) => p.ours).map((p) => p.label)]));
    assert.deepStrictEqual(by['in a retreat episode at death'], ['retreat:threat']);
    assert.deepStrictEqual(by['a stay in the last 15 s'], ['stay:hold']);
    assert.deepStrictEqual(by['heroes hitting it'], ['1 hero']);
    assert.strictEqual(by['HP when a hero first hit it in the last 15 s'].length, 1);
});

test('ledger --by lane splits the creep lines per lane and --by pos adds the deaths, every split counting every game', () => {
    const s = store({ den_A_rad_1: denies([100, 110]) });
    const result = ledger(s, ['den']);
    const byLane = split(result, 'lane');
    assert.deepStrictEqual(Object.keys(byLane.values), ['mid']);
    assert.strictEqual(byLane.values.mid.games[0].ours.miss.denied, 2);
    assert.strictEqual(byLane.reaches({ measure: 'deaths', line: 'duel' }), false);
    assert.strictEqual(split(result, 'pos').reaches({ measure: 'deaths', line: 'duel' }), true);
    assert.throws(() => split(result, 'x'), /--by takes lane or pos/);
});
