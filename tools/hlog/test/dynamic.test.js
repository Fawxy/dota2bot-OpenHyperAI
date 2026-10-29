'use strict';
const test = require('node:test');
const assert = require('node:assert');
const D = require('../dynamic');

// Map points: Radiant safe lane (bot) near its T1, mid near the Radiant T2, top near the Radiant T2, Radiant base, jungle.
const BOT = [-360, -6256], MID = [-1544, -1408], TOP = [-6501, -872], BASE = [-5920, -5352], JUNGLE = [-2500, 2500];
const FOUNTAIN = [-6850, -6461];

/** A bot with one snapshot per second from `from` to `to`; `at(t)` returns { p: [x, y], deaths?, lh? }, or null for no
 *  snapshot (a dead bot logs none, as in real logs). */
function bot(pid, team, at, from = 0, to = 700) {
    const snaps = [];
    for (let t = from; t <= to; t++) {
        const s = at(t);
        if (!s) continue;
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
    assert.strictEqual(D.laneLabel(FOUNTAIN), 'base');
    assert.strictEqual(D.laneLabel(JUNGLE), 'other');
});

test('an encounter needs the pair apart for 5 s first; onsets within 3 s merge', () => {
    const far = [6000, 6000];
    // Radiant hero stands mid all game; the Dire hero comes close at 10-20, leaves 3 s (no new), leaves 6 s then returns (new).
    const near = t => (t >= 10 && t < 20) || (t >= 23 && t < 30) || (t >= 36 && t < 40);
    const S = D.series(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: near(t) ? [MID[0] + 500, MID[1]] : far }))]));
    assert.strictEqual(D.encounters(S, 0, 60), 2);
});

test('a dead hero (snapshot gap across a deaths increment) cannot start an encounter', () => {
    // Dire dies mid at 10 (no snapshots 11-39), respawns in fountain at 40. Radiant reaches mid at 30.
    const dire = bot(5, 3, t => (t <= 10 ? { p: MID } : t < 40 ? null : { p: [7020, 6345], deaths: 1 }), 0, 60);
    const rad = bot(0, 2, t => ({ p: t < 30 ? [6000, -6000] : MID }), 0, 60);
    const S = D.series(game([rad, dire]));
    assert.strictEqual(S[5].sec[20].alive, 0);
    assert.strictEqual(D.encounters(S, 0, 60), 0);
});

test('encounter onsets join the encounter only within 3 s of its first onset', () => {
    // Three Dire heroes reach the Radiant hero at 10, 12 and 14: 10 and 12 are one encounter, 14 starts another.
    const far = [6000, 6000];
    const dire = [10, 12, 14].map((t0, k) => bot(5 + k, 3, t => ({ p: t >= t0 ? [MID[0] + 300, MID[1]] : far }), 0, 30));
    const S = D.series(game([bot(0, 2, () => ({ p: MID }), 0, 30), ...dire]));
    assert.strictEqual(D.encounters(S, 0, 30), 2);
});

test('pairs already together at the window start do not open an encounter', () => {
    const S = D.series(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, () => ({ p: MID }))]));
    assert.strictEqual(D.encounters(S, 0, 700), 1);
    assert.strictEqual(D.encounters(S, 600, 700), 0);
});

test('fights are runs of 3+ deaths with <= 15 s between deaths', () => {
    assert.strictEqual(D.fights([{ t: 100 }, { t: 110 }, { t: 124 }], 0, 600), 1);
    assert.strictEqual(D.fights([{ t: 100 }, { t: 120 }, { t: 140 }], 0, 600), 0);
    assert.strictEqual(D.fights([{ t: 100 }, { t: 101 }], 0, 600), 0);
});

test('a death is dated before its snapshot gap; a bot dead at the end adds a death', () => {
    // Dies at 50 (gap to 70), dies again at 100 and stays dead past the other bot's last snapshot (200).
    const a = bot(0, 2, t => (t <= 50 ? { p: MID } : t < 70 ? null : t <= 100 ? { p: MID, deaths: 1 } : null), 0, 200);
    const S = D.series(game([a, bot(1, 2, () => ({ p: MID }), 0, 200)]));
    assert.deepStrictEqual(D.deathTimes(S).map(d => d.t), [50, 100]);
    assert.strictEqual(S[0].sec[150].alive, 0);
});

test('a rotation is 10+ s in another lane region before 10:00; shorter trips do not count', () => {
    const trip = (a, b) => t => ({ p: t >= a && t < b ? TOP : BOT });
    const s1 = D.series(game([bot(0, 2, trip(400, 412))]))[0];
    s1.home = 'bot';
    assert.strictEqual(D.rotations(s1, 600), 1);
    const s2 = D.series(game([bot(0, 2, trip(400, 408))]))[0];
    s2.home = 'bot';
    assert.strictEqual(D.rotations(s2, 600), 0);
    // 5 s top, 3 s jungle, 6 s top: the short jungle stretch keeps the run open (11 lane seconds).
    const s3 = D.series(game([bot(0, 2, t => ({ p: t >= 400 && t < 405 ? TOP : t >= 405 && t < 408 ? JUNGLE : t >= 408 && t < 414 ? TOP : BOT }))]))[0];
    s3.home = 'bot';
    assert.strictEqual(D.rotations(s3, 600), 1);
    // 6 s top then 6 s mid: a lane change closes the run, neither reaches 10 s.
    const s4 = D.series(game([bot(0, 2, t => ({ p: t >= 400 && t < 406 ? TOP : t >= 406 && t < 412 ? MID : BOT }))]))[0];
    s4.home = 'bot';
    assert.strictEqual(D.rotations(s4, 600), 0);
});

test('lane exit is the first minute from 5:00 with under half of the next minute in the home lane', () => {
    const s = D.series(game([bot(0, 2, t => ({ p: t < 480 ? BOT : JUNGLE }), 0, 900)]))[0];
    s.home = 'bot';
    assert.strictEqual(D.laneExit(s, 900), 480);
    const stay = D.series(game([bot(0, 2, () => ({ p: BOT }), 0, 900)]))[0];
    stay.home = 'bot';
    assert.strictEqual(D.laneExit(stay, 900), undefined);
    // A 40 s base trip in the 6:00 minute is not a lane exit.
    const shop = D.series(game([bot(0, 2, t => ({ p: t >= 360 && t < 400 ? BASE : BOT }), 0, 900)]))[0];
    shop.home = 'bot';
    assert.strictEqual(D.laneExit(shop, 900), undefined);
});

test('a teleport-sized jump landing by an ally is a TP join; a respawn or a TP to base is not', () => {
    const ally = bot(1, 2, () => ({ p: TOP }), 600, 700);
    const tp = bot(0, 2, t => ({ p: t < 650 ? BOT : TOP }), 600, 700);
    let S = D.series(game([tp, ally]));
    assert.strictEqual(D.tpJoins(S, S[0], 600, 700), 1);
    // Dies on bot at 640, respawns at 660 in fountain next to an ally standing there.
    const inFountain = bot(1, 2, () => ({ p: FOUNTAIN }), 600, 700);
    const respawn = bot(0, 2, t => (t <= 640 ? { p: BOT } : t < 660 ? null : { p: FOUNTAIN, deaths: 1 }), 600, 700);
    S = D.series(game([respawn, inFountain]));
    assert.strictEqual(D.tpJoins(S, S[0], 600, 700), 0);
    const toBase = bot(0, 2, t => ({ p: t < 650 ? TOP : FOUNTAIN }), 600, 700);
    S = D.series(game([toBase, inFountain]));
    assert.strictEqual(D.tpJoins(S, S[0], 600, 700), 0);
});

test('standing still outside base for 10+ s is one idle episode; in base, fountain or dead it is not', () => {
    const s = D.series(game([bot(0, 2, t => ({ p: t >= 100 && t < 120 ? JUNGLE : [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] }))]))[0];
    assert.strictEqual(D.idles(s, 0, 200), 1);
    const b = D.series(game([bot(0, 2, () => ({ p: BASE }))]))[0];
    assert.strictEqual(D.idles(b, 0, 200), 0);
    const f = D.series(game([bot(0, 2, () => ({ p: FOUNTAIN }))]))[0];
    assert.strictEqual(D.idles(f, 0, 200), 0);
    // Dies in the jungle at 50, respawns at 90 in fountain, then keeps moving.
    const moving = t => ({ p: [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] });
    const d = D.series(game([bot(0, 2, t => (t <= 50 ? moving(t) : t < 90 ? null : { ...moving(t), deaths: 1 }), 0, 200)]))[0];
    assert.strictEqual(D.idles(d, 0, 200), 0);
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

test('dynamicMetrics: lineup-position keys from ev=bot pos= sit beside the role keys; mismatches are counted', () => {
    // Behaviour roles: 0 mid (2), 1 safe (1), 2 off (3), 3 and 4 supports. The lineup swaps 1 and 2 (pos 3 and pos 1).
    const rad = [
        bot(0, 2, t => ({ p: MID, lh: Math.floor(t / 10) })),
        bot(1, 2, t => ({ p: BOT, lh: Math.floor(t / 8) })),
        bot(2, 2, t => ({ p: TOP, lh: Math.floor(t / 20) })),
        bot(3, 2, t => ({ p: BOT, lh: Math.floor(t / 60) })),
        bot(4, 2, t => ({ p: TOP, lh: Math.floor(t / 100) })),
    ];
    [[0, 2], [1, 3], [2, 1], [3, 4], [4, 5]].forEach(([i, pos]) => (rad[i].profiles = [{ ev: 'bot', pos: 5 }, { ev: 'bot', pos }]));
    const m = D.dynamicMetrics(game(rad));
    assert.deepStrictEqual(m.lpos, { 0: 2, 1: 3, 2: 1, 3: 4, 4: 5 });
    assert.strictEqual(m.lh_at_10.r1, 75); // role key unchanged
    assert.strictEqual(m.lh_at_10_lpos.r1, 30);
    assert.strictEqual(m.lh_at_10_lpos.r3, 75);
    assert.strictEqual(m.role_mismatch, 2);
});

test('dynamicMetrics: a team whose positions are not exactly 1-5 gets no lpos keys and a warning', () => {
    // Pre-Dire-fix logs: every Dire bot says pos=1.
    const dire = [0, 1, 2, 3, 4].map(i => bot(5 + i, 3, t => ({ p: MID, lh: Math.floor(t / (10 + i)) })));
    dire.forEach(b => (b.profiles = [{ ev: 'bot', pos: 1 }]));
    const m = D.dynamicMetrics(game(dire));
    assert.deepStrictEqual(m.lpos, {});
    assert.deepStrictEqual(m.lh_at_10_lpos, {});
    assert.strictEqual(m.role_mismatch, 0);
    assert.ok(m.warnings.some(w => /team 3: lineup positions 1,1,1,1,1 are not 1-5/.test(w)), m.warnings.join('; '));
});

test('dynamicMetrics: our pcall errors, console errors and the censoring flag are separate keys', () => {
    const g = game([bot(0, 2, () => ({ p: MID }))], [{ ev: 'lua_error', t: 5, pid: 0 }]);
    g.errors = [{ text: 'Script Runtime Error: error in error handling' }, { text: 'stack traceback:' }];
    g.squelched = true;
    g.squelches = 2;
    g.errorSquelches = 1;
    const m = D.dynamicMetrics(g);
    assert.strictEqual(m.lua_error, 3); // NF-001 meaning kept: ours plus every console error line
    assert.strictEqual(m.lua_error_ours, 1);
    assert.strictEqual(m.console_errors, 1);
    assert.strictEqual(m.console_squelches, 2);
    assert.strictEqual(m.console_censored, true);
    g.errorSquelches = 0; // squelched repeats of a non-error message do not censor error counts
    assert.strictEqual(D.dynamicMetrics(g).console_censored, false);
});

// World events (slice 23).
const ev = (name, t, f) => ({ ev: name, t, ...f });

test('world metrics: rune shares by the mid, sentries, smokes merged, events absent read undefined', () => {
    const S = D.series(game([bot(1, 2, () => ({ p: MID }), 0, 800), bot(2, 2, () => ({ p: BOT }), 0, 800), bot(6, 3, () => ({ p: [6000, 6000] }), 0, 800)]));
    const role = { 1: 2, 2: 4, 6: 2 };
    const events = [
        ev('rune_pickup', 120, { pid: 1, team: 2, kind: 'water' }),
        ev('rune_pickup', 240, { pid: 2, team: 2, kind: 'water' }),
        ev('rune_pickup', 360, { pid: 1, team: 2, kind: 'power' }),
        ev('ward_place', 50, { pid: 2, team: 2, kind: 'sentry' }),
        ev('ward_place', 40, { pid: 2, team: 2, kind: 'obs' }),
        ev('smoke_use', 500, { pid: 1, team: 2 }),
        ev('smoke_use', 501, { pid: 2, team: 2 }),
        ev('smoke_use', 600, { pid: 1, team: 2 }),
        ev('smoke_use', 602, { pid: 2, team: 2 }),
        ev('smoke_use', 604, { pid: 1, team: 2 }),
        ev('smoke_use', -50, { pid: 1, team: 2 }),
    ];
    const m = D.worldMetrics(game([], events), S, role, [], 800);
    assert.strictEqual(m.mid_water_rune_pct[2], 0.5);
    assert.strictEqual(m.mid_power_rune_pct[2], 1);
    assert.strictEqual(m.mid_power_rune_pct[3], undefined);
    assert.strictEqual(m.power_rune_pickups[2], 1);
    assert.strictEqual(m.first_sentry_time.r4, 50);
    assert.deepStrictEqual(m.sentry_by_90s, { 2: 1, 3: 0 });
    // 500/501 one group; 600/602 one group; 604 is 4 s after its group's first, so a new one; the pregame smoke is not counted.
    assert.strictEqual(m.smoke_uses_per_team[2], 3);
    const none = D.worldMetrics(game([], []), S, role, [], 800);
    assert.strictEqual(none.mid_power_rune_pct, undefined);
    assert.strictEqual(none.first_t1_time, undefined);
});

test('world metrics: tp joins need distance, the 10:00-30:00 window and an ally at the landing', () => {
    const S = D.series(game([bot(1, 2, () => ({ p: MID }), 0, 1900), bot(2, 2, () => ({ p: BOT }), 0, 1900)]));
    const tp = (t, x, y, d) => ev('tp', t, { pid: 2, team: 2, x, y, dist: d });
    const events = [tp(700, MID[0] + 300, MID[1], 5000), tp(800, MID[0], MID[1], 500), tp(500, MID[0], MID[1], 5000), tp(900, 6000, 6000, 5000)];
    assert.strictEqual(D.worldMetrics(game([], events), S, {}, [], 1900).tp_joins_per_team_ev[2], 1);
});

test('world metrics: first T1, cash-in after a 3+ kill burst, Roshan de-duplicated and followed by a tower', () => {
    const S = D.series(game([bot(1, 2, () => ({ p: MID }), 0, 2000)]));
    // Radiant kills three Dire heroes at 900-920; a Dire tower falls at 1000 (cash-in). A later burst at 1500 has no tower.
    const deaths = [900, 910, 920].map(t => ({ t, team: 3 })).concat([1500, 1505, 1510].map(t => ({ t, team: 3 })));
    const events = [
        ev('building_fall', 700, { team: 2, kind: 'tower', tier: 2 }),
        ev('building_fall', 650, { team: 3, kind: 'tower', tier: 1 }),
        ev('building_fall', 1000, { team: 3, kind: 'tower', tier: 2 }),
        ev('roshan_kill', 1200, { team: 2, at: 1199.5 }),
        ev('roshan_kill', 1200.2, { team: 3, at: 1199.5 }),
        ev('aegis', 1203, { pid: 1, team: 2 }),
        ev('building_fall', 1300, { team: 2, kind: 'rax', id: 1 }),
        ev('building_fall', 1400, { team: 3, kind: 'tower', tier: 3 }),
    ];
    const m = D.worldMetrics(game([], events), S, {}, deaths, 2000);
    assert.strictEqual(m.first_t1_time, 650);
    assert.strictEqual(m.cash_in_kills_pct[2], 0.5);
    assert.strictEqual(m.cash_in_kills_pct[3], undefined);
    assert.strictEqual(m.first_roshan_time, 1200);
    // The Radiant aegis team's own rax at 1300 does not count; the Dire tower at 1400 does.
    assert.strictEqual(m.towers_after_roshan_240, 1);
});

test('wisdom proxy: a hero 3 s within 300 of the shrine by fill + 15 s takes it', () => {
    const SH = [-7948, 768];
    // Takes the 7:00 fill at 7:10-7:13; reaches the 14:00 fill at 14:20 (too late).
    const at = t => ({ p: (t >= 430 && t < 433) || (t >= 860 && t < 870) ? [SH[0] + 100, SH[1]] : TOP });
    const S = D.series(game([bot(1, 2, at, 0, 900)]));
    assert.strictEqual(D.wisdom(S, 2, 900), 0.5);
    assert.strictEqual(D.wisdom(S, 2, 400), undefined);
});

test('auditedSteals: a support last hit counts when a logged core was attacking the creep or within range + 150', () => {
    const S = D.series(game([bot(0, 2, () => ({ p: BOT })), bot(3, 2, () => ({ p: BOT }))]));
    S[3].sec[100].mode = 'laning';
    const lpos = { 0: 1, 3: 5 };
    const death = (t, by, f) => ({ ev: 'creep_death', t, team: 2, kind: 'melee', by, ...f });
    const events = [
        death(100.2, 3, { p1d: 300, p1r: 150 }), // in range + 150: counted, with the support's mode
        death(110, 3, { p1d: 900, p1r: 150, p1t: 1 }), // attacking: counted
        death(120, 3, { p1d: 301, p1r: 150 }), // just beyond: not
        death(130, 3, {}), // no core logged: not
        death(140, 0, { p1d: 50, p1r: 150 }), // the core's own last hit: not
        death(610, 3, { p1d: 50, p1r: 150 }), // after until: not
    ];
    const cases = D.auditedSteals({ events }, S, lpos, 600);
    assert.deepStrictEqual(cases.map(c => c.t), [100.2, 110]);
    assert.strictEqual(cases[0].mode, 'laning');
    assert.deepStrictEqual(cases[1].cores, [{ core: 1, d: 900, r: 150, attacking: true }]);
    const swung = D.auditedSteals({ events: [death(100.2, 3, { p1d: 300, p1r: 150, bm: 'attack', bs: 0.4 })] }, S, lpos, 600);
    assert.deepStrictEqual([swung[0].mode, swung[0].snapMode, swung[0].swing], ['attack', 'laning', 0.4], 'bm (swing-start mode) wins over the snapshot');
    assert.strictEqual(D.auditedSteals({ events: [] }, S, lpos, 600), undefined, 'no ev=creep_death: undefined, not 0');
    assert.strictEqual(D.auditedSteals({ events }, S, {}, 600), undefined, 'no lineup positions: undefined');
});
