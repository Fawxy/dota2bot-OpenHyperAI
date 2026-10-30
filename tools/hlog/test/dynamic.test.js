'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const D = require('../dynamic');
const { Store } = require('../store');

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

/** A game object (as `game`) written back as [HEV] lines, with its console errors and squelch notices after the events. */
function logText(g) {
    const lines = [];
    const fmt = (t, ev, f) => `[HEV] t=${Number(t).toFixed(3)} ev=${ev}` + Object.entries(f).map(([k, v]) => ` ${k}=${v}`).join('');
    for (const b of Object.values(g.bots)) {
        const t0 = b.snaps.length ? b.snaps[0].t : 0;
        const profiles = b.profiles.length ? b.profiles : [{}];
        for (const p of profiles) lines.push([t0, fmt(t0, 'bot', { pid: b.pid, hero: b.hero, team: b.team, ...(p.pos !== undefined ? { pos: p.pos } : {}) })]);
        for (const s of b.snaps) lines.push([s.t, fmt(s.t, 'snap', { pid: s.pid, ...(s.x !== undefined ? { x: s.x, y: s.y } : {}), alive: s.alive, deaths: s.deaths, lh: s.lh })]);
    }
    for (const { ev, t, ...f } of g.events) lines.push([t, fmt(t, ev, f)]);
    lines.sort((a, b) => a[0] - b[0]);
    return [...lines.map(l => l[1]), ...(g.console || [])].join('\n') + '\n';
}

/** The game in an in-memory log store; returns { store, file } (close store.db when done). */
function stored(g) {
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-dyn-')), 'a.log');
    fs.writeFileSync(file, logText(g));
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return { store, file };
}

/** dynamicMetrics of the game through the log store. */
function metricsOf(g) {
    const { store, file } = stored(g);
    try {
        return D.dynamicMetrics(store, file, 1);
    } finally {
        store.db.close();
    }
}

/** A hero standing at p, dead from `die` (no snapshots) until `back`, where it respawns in its fountain with deaths=1. */
const dies = (pid, team, p, die, back, to = 700) =>
    bot(pid, team, t => (t <= die ? { p } : t < back ? null : { p: team === 2 ? FOUNTAIN : [7020, 6345], deaths: 1 }), 0, to);

test('an encounter needs the pair apart for 5 s first; onsets within 3 s merge', () => {
    const far = [6000, 6000];
    // Radiant hero stands mid all game; the Dire hero comes close at 10-19, then away 3 s (no new), 4 s (no new) and 5 s (new).
    const near = t => (t >= 10 && t < 20) || (t >= 23 && t < 30) || (t >= 34 && t < 37) || (t >= 42 && t < 46);
    const m = metricsOf(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: near(t) ? [MID[0] + 500, MID[1]] : far }))]));
    assert.strictEqual(m.encounters_per_10min.before10, 2);
});

test('a dead hero (snapshot gap across a deaths increment) cannot start an encounter', () => {
    // Dire dies mid at 10 (no snapshots 11-19), respawns in fountain at 20. Radiant reaches mid at 12.
    const rad = () => bot(0, 2, t => ({ p: t < 12 ? [6000, -6000] : MID }), 0, 60);
    const g = game([rad(), dies(5, 3, MID, 10, 20, 60)]);
    assert.strictEqual(D.series(g)[5].sec[15].alive, 0);
    assert.strictEqual(metricsOf(g).encounters_per_10min.before10, 0);
    // The same gap while the Dire hero is alive (no deaths increment, so the gap is not death) is an encounter.
    const alive = bot(5, 3, t => (t <= 10 || t >= 20 ? { p: MID } : null), 0, 60);
    assert.strictEqual(metricsOf(game([rad(), alive])).encounters_per_10min.before10, 1);
});

test('an encounter needs the pair within 1200 units', () => {
    const at = d => metricsOf(game([bot(0, 2, () => ({ p: MID }), 0, 60), bot(5, 3, t => ({ p: t >= 20 ? [MID[0] + d, MID[1]] : [6000, 6000] }), 0, 60)]));
    assert.strictEqual(at(1200).encounters_per_10min.before10, 1);
    assert.strictEqual(at(1201).encounters_per_10min.before10, 0);
});

test('encounter onsets join the encounter only within 3 s of its first onset', () => {
    // Three Dire heroes reach the Radiant hero at 10, 12 and 14: 10 and 12 are one encounter, 14 starts another.
    const far = [6000, 6000];
    const dire = [10, 12, 14].map((t0, k) => bot(5 + k, 3, t => ({ p: t >= t0 ? [MID[0] + 300, MID[1]] : far }), 0, 30));
    assert.strictEqual(metricsOf(game([bot(0, 2, () => ({ p: MID }), 0, 30), ...dire])).encounters_per_10min.before10, 2);
});

test('pairs already together at the window start do not open an encounter; after 10:00 is a rate per 10 min', () => {
    const together = metricsOf(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, () => ({ p: MID }))]));
    assert.deepStrictEqual(together.encounters_per_10min, { before10: 1, after10: 0 });
    // Apart until 10:00, then the Dire hero walks up at 10:20 (end 11:00): one encounter in 60 s is 10 per 10 min.
    const late = metricsOf(game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: t >= 620 ? MID : [6000, 6000] }))]));
    assert.deepStrictEqual(late.encounters_per_10min, { before10: 0, after10: 10 });
});

test('fights are runs of 3+ deaths with <= 15 s between deaths', () => {
    const fightsOf = ts => metricsOf(game([...ts.map((t, k) => dies(k, 2, MID, t, t + 20)), bot(9, 3, () => ({ p: [6000, 6000] }))])).fights_per_10min.before10;
    assert.strictEqual(fightsOf([100, 110, 124]), 1);
    assert.strictEqual(fightsOf([100, 120, 140]), 0);
    assert.strictEqual(fightsOf([100, 101]), 0);
});

test('a death is dated before its snapshot gap; a bot dead at the end adds a death', () => {
    // Dies at 50 (gap to 70), dies again at 100 and stays dead past the other bot's last snapshot (200).
    const a = bot(0, 2, t => (t <= 50 ? { p: MID } : t < 70 ? null : t <= 100 ? { p: MID, deaths: 1 } : null), 0, 200);
    const g = game([a, bot(1, 2, () => ({ p: MID }), 0, 200)]);
    const { store, file } = stored(g);
    const rows = store.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'dynamic_deaths.sql'), 'utf8'), { file, game: 1 });
    store.db.close();
    assert.deepStrictEqual(rows.map(r => [r.t, r.n]), [[50, 1], [100, 1]]);
    assert.strictEqual(D.series(g)[0].sec[150].alive, 0);
    const m = metricsOf(g);
    assert.deepStrictEqual([m.deaths_total, m.deaths_before_10[2]], [2, 2]);
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

test('the later of two snapshots at one time wins, for the series and for last hits at 10:00', () => {
    const far = [6000, 6000];
    // Dire: far, then at 20 two lines (mid, then far), far again, mid from 30. Second 20 is far, so the only onset is 30.
    const dire = bot(5, 3, t => ({ p: t >= 30 ? MID : far }), 0, 60);
    dire.snaps.splice(20, 0, { ...dire.snaps[20], x: MID[0], y: MID[1] });
    const rad = bot(0, 2, t => ({ p: MID, lh: t === 600 ? 5 : 0 }), 0, 700);
    rad.snaps.splice(601, 0, { ...rad.snaps[600], lh: 7 });
    const m = metricsOf(game([rad, dire]));
    assert.strictEqual(m.encounters_per_10min.before10, 1);
    assert.strictEqual(m.lh_at_10.r2, 7);
});

test('pre-game seconds open no encounter: the scan starts at 0:00', () => {
    // Together from -20 to -3, apart -2 to 2, together from 3: the gap straddles 0:00, so 3 is the only onset.
    const dire = bot(5, 3, t => ({ p: t >= -2 && t <= 2 ? [6000, 6000] : MID }), -20, 60);
    assert.strictEqual(metricsOf(game([bot(0, 2, () => ({ p: MID }), -20, 60), dire])).encounters_per_10min.before10, 1);
});

test('fights after 10:00 are a rate per 10 min; deaths 15 s apart join, 16 s do not', () => {
    const after = ts => metricsOf(game([...ts.map((t, k) => dies(k, 2, MID, t, t + 20, 900)), bot(9, 3, () => ({ p: [6000, 6000] }), 0, 900)])).fights_per_10min;
    assert.deepStrictEqual(after([700, 715, 730]), { before10: 0, after10: 2 }); // one fight in the 300 s after 10:00
    assert.deepStrictEqual(after([700, 716, 732]), { before10: 0, after10: 0 });
});

test('a deaths counter that rises by 2 across one gap is two deaths at the snapshot before it', () => {
    const a = bot(0, 2, t => (t <= 50 ? { p: MID } : t < 80 ? null : { p: FOUNTAIN, deaths: 2 }), 0, 200);
    const m = metricsOf(game([a, bot(1, 3, () => ({ p: [6000, 6000] }), 0, 200)]));
    assert.deepStrictEqual([m.deaths_total, m.deaths_before_10[2]], [2, 2]);
});

test('the second game of a log is read on its own', () => {
    const one = game([bot(0, 2, () => ({ p: MID })), bot(5, 3, () => ({ p: MID }))]); // together: 1 encounter
    const two = game([bot(0, 2, () => ({ p: MID })), bot(5, 3, t => ({ p: [6000, 6000] }))]); // never: 0
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-dyn-')), 'a.log');
    fs.writeFileSync(file, logText(one) + logText(two));
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    const enc = n => D.dynamicMetrics(store, file, n).encounters_per_10min.before10;
    assert.deepStrictEqual([enc(1), enc(2)], [1, 0]);
    store.db.close();
});

test('the game end counts snapshots without a position, as the series does', () => {
    // Radiant's last snapshot (t=900) has no x: end is 900, not 660, and Dire's snapshots stopping at 700 make it dead at the end.
    const rad = bot(0, 2, () => ({ p: MID }), 0, 700);
    rad.snaps.push({ ev: 'snap', t: 900, pid: 0, alive: 1, deaths: 0, lh: 0 });
    const m = metricsOf(game([rad, bot(5, 3, () => ({ p: [6000, 6000] }), 0, 700)]));
    assert.strictEqual(m.end, 900);
    assert.strictEqual(m.deaths_total, 2);
});

test('standing still outside base for 10+ s is one idle episode; in base, fountain or dead it is not', () => {
    const idleOf = (...bots) => metricsOf(game(bots)).idle_10s;
    assert.strictEqual(idleOf(bot(0, 2, t => ({ p: t >= 100 && t < 120 ? JUNGLE : [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] }))), 1);
    // Still at 100-109 (a spot 250 from both jitter points) is 9 s from the first still second: not yet 10.
    assert.strictEqual(idleOf(bot(0, 2, t => ({ p: t >= 100 && t < 110 ? [JUNGLE[0] + 250, JUNGLE[1]] : [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] }))), 0);
    assert.strictEqual(idleOf(bot(0, 2, t => ({ p: t >= 100 && t < 111 ? [JUNGLE[0] + 250, JUNGLE[1]] : [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] }))), 1);
    assert.strictEqual(idleOf(bot(0, 2, () => ({ p: BASE }))), 0);
    assert.strictEqual(idleOf(bot(0, 2, () => ({ p: FOUNTAIN }))), 0);
    // Dies in the jungle at 50, respawns at 90 in fountain, then keeps moving.
    const moving = t => ({ p: [JUNGLE[0] + (t % 2) * 500, JUNGLE[1]] });
    assert.strictEqual(idleOf(bot(0, 2, t => (t <= 50 ? moving(t) : t < 90 ? null : { ...moving(t), deaths: 1 }), 0, 200)), 0);
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
    const m = metricsOf(game(rad, events));
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
    const m = metricsOf(game(rad));
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
    const m = metricsOf(game(dire));
    assert.deepStrictEqual(m.lpos, {});
    assert.deepStrictEqual(m.lh_at_10_lpos, {});
    assert.strictEqual(m.role_mismatch, 0);
    assert.ok(m.warnings.some(w => /team 3: lineup positions 1,1,1,1,1 are not 1-5/.test(w)), m.warnings.join('; '));
});

test('dynamicMetrics: our pcall errors, console errors and the censoring flag are separate keys', () => {
    const g = game([bot(0, 2, () => ({ p: MID }))], [{ ev: 'lua_error', t: 5, pid: 0 }]);
    const squelch = '[VScript] Message count limit of 10 hit';
    // A squelch notice after a non-error line, then two error lines and a notice right after them.
    g.console = [squelch, 'Script Runtime Error: error in error handling', 'stack traceback:', squelch];
    const m = metricsOf(g);
    assert.strictEqual(m.lua_error, 3); // NF-001 meaning kept: ours plus every console error line
    assert.strictEqual(m.lua_error_ours, 1);
    assert.strictEqual(m.console_errors, 1);
    assert.strictEqual(m.console_squelches, 2);
    assert.strictEqual(m.console_censored, true);
    g.console = [squelch, 'Script Runtime Error: error in error handling']; // squelched repeats of a non-error message do not censor
    assert.strictEqual(metricsOf(g).console_censored, false);
});

test('dynamicMetrics: a game not in the store, or with no hero, throws', () => {
    const { store, file } = stored(game([bot(0, 2, () => ({ p: MID }))]));
    assert.throws(() => D.dynamicMetrics(store, file + '.x', 1), /is not in the store/);
    store.db.close();
    assert.throws(() => metricsOf(game([], [{ ev: 'lua_error', t: 5, pid: 0 }])), /no hero with a team and a snapshot/);
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

test('stackAttempts: one entry per ev=stack line before until; empty without any', () => {
    const line = (t, f) => ({ ev: 'stack', t, pid: 4, min: 3, ...f });
    const events = [
        line(242, { res: 'stacked', why: 'ok', camp: 15, type: 'small', aggro: 55.4, before: 3, after: 6, away: 12.8, death: 0 }),
        line(300, { min: 5, res: 'skip', why: 'enemy-near' }),
        line(480, { min: 7, res: 'failed', why: 'dead', away: 9, death: 1 }),
    ];
    const a = D.stackAttempts({ events }, 400);
    assert.deepStrictEqual(a.map(x => x.res), ['stacked', 'skip']);
    assert.strictEqual(a[0].death, false);
    assert.strictEqual(D.stackAttempts({ events }, 600)[2].death, true);
    assert.deepStrictEqual(D.stackAttempts({ events: [] }, 600), []);
});

test('stackAttempts: cause of a not-stacked attempt from the :59.5 sample', () => {
    const ns = f => ({ ev: 'stack', t: 245, pid: 4, min: 3, res: 'not_stacked', why: 'ok', before: 3, ...f });
    const cause = f => D.stackAttempts({ events: [ns(f)] }, 600)[0].cause;
    assert.strictEqual(cause({ box59: 0, bot59: 1, vis59: 1, after: 3 }), 'bot-in-box');
    assert.strictEqual(cause({ box59: 2, bot59: 0, vis59: 1, after: 3 }), 'camp-in-box');
    assert.strictEqual(cause({ box59: 0, bot59: 0, vis59: 0, after: '?' }), 'unseen');
    assert.strictEqual(cause({ box59: 0, bot59: 0, vis59: 1, after: 2 }), 'no-spawn');
    assert.strictEqual(cause({ box59: '?', after: 3 }), undefined);
    assert.strictEqual(D.stackAttempts({ events: [ns({ res: 'failed', why: 'dead' })] }, 600)[0].cause, 'dead');
    assert.strictEqual(D.stackAttempts({ events: [ns({ res: 'stacked', box59: 0 })] }, 600)[0].cause, undefined);
});

test('stackAttempts: left59 names the camp neutrals still in the box at :59.5 (user replay s4solo1)', () => {
    const left = n59 => D.stackAttempts({ events: [{ ev: 'stack', t: 245, pid: 2, min: 3, res: 'not_stacked', why: 'ok', n59 }] }, 600)[0].left59;
    assert.strictEqual(left('satyr_hellcaller:120:in:-,satyr_soulstealer:900:out:a,dead'), 'satyr_hellcaller:-');
    assert.strictEqual(left('ogre_mauler:900:out:a,ogre_magi:?'), '-');
    assert.strictEqual(left('?'), undefined);
    assert.strictEqual(left(undefined), undefined);
});

test('stackAttempts: lane carries the lane creeps near the camp after the hit (user, s4solo7ab: a pull)', () => {
    const one = e => D.stackAttempts({ events: [{ ev: 'stack', t: 245, pid: 2, min: 3, res: 'stacked', why: 'ok', ...e }] }, 600)[0].lane;
    assert.strictEqual(one({ lane: 4 }), 4);
    assert.strictEqual(one({}), undefined);
});
