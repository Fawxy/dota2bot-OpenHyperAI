'use strict';
const test = require('node:test');
const assert = require('node:assert');
const D = require('../dynamic');

// Map points: Radiant safe lane (bot) near its T1, mid near the Radiant T2, top near the Radiant T2, Radiant base, jungle.
const BOT = [-360, -6256], MID = [-1544, -1408], TOP = [-6501, -872], BASE = [-5920, -5352], JUNGLE = [-2500, 2500];

/** A bot with one snapshot per second from `from` to `to`; `at(t)` returns { p: [x, y], alive?, deaths?, lh? }. */
function bot(pid, team, at, from = 0, to = 700) {
    const snaps = [];
    for (let t = from; t <= to; t++) {
        const s = at(t);
        snaps.push({ ev: 'snap', t, pid, x: s.p[0], y: s.p[1], alive: s.alive === false ? 0 : 1, deaths: s.deaths || 0, lh: s.lh || 0 });
    }
    return { pid, hero: `h${pid}`, team, snaps, profiles: [] };
}
const game = (bots, events = []) => ({ bots: Object.fromEntries(bots.map(b => [b.pid, b])), events, errors: [] });

test('lane labels follow the tower polylines and the bases', () => {
    assert.strictEqual(D.laneLabel(BOT), 'bot');
    assert.strictEqual(D.laneLabel(MID), 'mid');
    assert.strictEqual(D.laneLabel(TOP), 'top');
    assert.strictEqual(D.laneLabel(BASE), 'base');
    assert.strictEqual(D.laneLabel(JUNGLE), 'other');
});

test('an encounter needs the pair apart for 5 s first; onsets within 3 s merge', () => {
    const far = [6000, 6000];
    // Radiant hero stands mid all game; the Dire hero comes close at 10-20, leaves 3 s (no new), leaves 6 s then returns (new).
    const near = t => (t >= 10 && t < 20) || (t >= 23 && t < 30) || (t >= 36 && t < 40);
    const S = D.series(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: near(t) ? [MID[0] + 500, MID[1]] : far }))]));
    assert.strictEqual(D.encounters(S, 0, 60), 2);
});

test('a dead hero cannot start an encounter', () => {
    const S = D.series(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: MID, alive: t < 100 ? false : true }))]));
    assert.strictEqual(D.encounters(S, 0, 90), 0);
});

test('fights are runs of 3+ deaths with <= 15 s between deaths', () => {
    assert.strictEqual(D.fights([{ t: 100 }, { t: 110 }, { t: 124 }], 0, 600), 1);
    assert.strictEqual(D.fights([{ t: 100 }, { t: 120 }, { t: 140 }], 0, 600), 0);
    assert.strictEqual(D.fights([{ t: 100 }, { t: 101 }], 0, 600), 0);
});

test('death times come from deaths counter increments', () => {
    const S = D.series(game([bot(0, 2, t => ({ p: MID, deaths: t >= 50 ? (t >= 80 ? 2 : 1) : 0 }))]));
    assert.deepStrictEqual(D.deathTimes(S).map(d => d.t), [50, 80]);
});

test('a rotation is 10+ s in another lane region before 10:00; shorter trips do not count', () => {
    const trip = (a, b) => t => ({ p: t >= a && t < b ? TOP : BOT });
    const s1 = D.series(game([bot(0, 2, trip(400, 412))]))[0];
    s1.home = 'bot';
    assert.strictEqual(D.rotations(s1, 600), 1);
    const s2 = D.series(game([bot(0, 2, trip(400, 408))]))[0];
    s2.home = 'bot';
    assert.strictEqual(D.rotations(s2, 600), 0);
});

test('lane exit is the first minute from 5:00 with under half of the next minute in the home lane', () => {
    const s = D.series(game([bot(0, 2, t => ({ p: t < 480 ? BOT : JUNGLE }), 0, 900)]))[0];
    s.home = 'bot';
    assert.strictEqual(D.laneExit(s, 900), 480);
    const stay = D.series(game([bot(0, 2, () => ({ p: BOT }), 0, 900)]))[0];
    stay.home = 'bot';
    assert.strictEqual(D.laneExit(stay, 900), undefined);
});

test('a teleport-sized jump landing by an ally is a TP join; a respawn jump is not', () => {
    const ally = bot(1, 2, () => ({ p: TOP }), 600, 700);
    const tp = bot(0, 2, t => ({ p: t < 650 ? BOT : TOP }), 600, 700);
    let S = D.series(game([tp, ally]));
    assert.strictEqual(D.tpJoins(S, S[0], 600, 700), 1);
    const respawn = bot(0, 2, t => ({ p: t < 650 ? BOT : TOP, alive: !(t >= 640 && t < 650) }), 600, 700);
    S = D.series(game([respawn, ally]));
    assert.strictEqual(D.tpJoins(S, S[0], 600, 700), 0);
});

test('standing still outside base for 10+ s is one idle episode; in base it is not', () => {
    const s = D.series(game([bot(0, 2, t => ({ p: t >= 100 && t < 120 ? JUNGLE : [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] }))]))[0];
    assert.strictEqual(D.idles(s, 0, 200), 1);
    const b = D.series(game([bot(0, 2, () => ({ p: BASE }))]))[0];
    assert.strictEqual(D.idles(b, 0, 200), 0);
});

test('dynamicMetrics: roles by last hits and home lane, deaths before 10:00, steals near a core', () => {
    // Radiant: mid core 0, safe-lane core 1 (bot), off-lane core 2 (top), supports 3 (bot, steals next to 1) and 4 (top).
    const rad = [
        bot(0, 2, t => ({ p: MID, lh: Math.floor(t / 10) })),
        bot(1, 2, t => ({ p: BOT, lh: Math.floor(t / 8) })),
        bot(2, 2, t => ({ p: TOP, lh: Math.floor(t / 20), deaths: t >= 300 ? 1 : 0 })),
        bot(3, 2, t => ({ p: [BOT[0] + 300, BOT[1]], lh: Math.floor(t / 60) })),
        bot(4, 2, t => ({ p: TOP, lh: Math.floor(t / 100) })),
    ];
    const events = [{ ev: 'lasthit', t: 200, pid: 3, n: 1 }, { ev: 'lasthit', t: 210, pid: 4, n: 1 }];
    const m = D.dynamicMetrics(game(rad, events));
    assert.strictEqual(m.roles.r2, 'h0');
    assert.strictEqual(m.roles.r1, 'h1');
    assert.strictEqual(m.roles.r3, 'h2');
    assert.strictEqual(m.roles.r4, 'h3');
    assert.strictEqual(m.deaths_before_10[2], 1);
    // Support 3 is 300 units from core 1: a steal. Support 4 is next to core 2 (top): also within 700.
    assert.strictEqual(m.ally_creep_steals[2], 2);
    assert.strictEqual(m.lh_at_10.r1, 75);
});
