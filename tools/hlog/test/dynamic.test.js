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

/** The heroes of the game through the log store (dynamic.js heroes), each with `sec[s]` = { x, y, alive, mode } from
 *  @dynamic_series (the per-second series the queries build on). */
function seriesOf(g) {
    const { store, file } = stored(g);
    try {
        const S = D.heroes(store, file, 1);
        for (const r of store.query(sql('dynamic_series'), { file, game: 1 })) if (S[r.pid]) (S[r.pid].sec ??= {})[r.s] = { x: r.x, y: r.y, alive: r.alive, mode: r.mode };
        return S;
    } finally {
        store.db.close();
    }
}
const sql = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

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
    assert.strictEqual(seriesOf(g)[5].sec[15].alive, 0);
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
    assert.strictEqual(seriesOf(g)[0].sec[150].alive, 0);
    const m = metricsOf(g);
    assert.deepStrictEqual([m.deaths_total, m.deaths_before_10[2]], [2, 2]);
});

test('a rotation is 10+ s in another lane region before 10:00; shorter trips do not count', () => {
    // Home is bot (1:00-5:00); each trip is after 5:00.
    const rot = at => seriesOf(game([bot(0, 2, at)]))[0].rot10;
    const trip = (a, b) => t => ({ p: t >= a && t < b ? TOP : BOT });
    assert.strictEqual(rot(trip(400, 410)), 1);
    assert.strictEqual(rot(trip(400, 409)), 0);
    // 5 s top, 3 s jungle, 6 s top: the short jungle stretch keeps the run open (11 lane seconds).
    assert.strictEqual(rot(t => ({ p: t >= 400 && t < 405 ? TOP : t >= 405 && t < 408 ? JUNGLE : t >= 408 && t < 414 ? TOP : BOT })), 1);
    // 5 s top, 9 s jungle, 6 s top: the gap closes the run, neither part reaches 10 s.
    assert.strictEqual(rot(t => ({ p: t >= 400 && t < 405 ? TOP : t >= 405 && t < 414 ? JUNGLE : t >= 414 && t < 420 ? TOP : BOT })), 0);
    // 6 s top then 6 s mid: a lane change closes the run, neither reaches 10 s; 10 s top then 10 s mid is two.
    assert.strictEqual(rot(t => ({ p: t >= 400 && t < 406 ? TOP : t >= 406 && t < 412 ? MID : BOT })), 0);
    assert.strictEqual(rot(t => ({ p: t >= 400 && t < 410 ? TOP : t >= 410 && t < 420 ? MID : BOT })), 2);
    // A run still open at 10:00 counts; one starting at 9:51 has 9 s before 10:00 and does not.
    assert.strictEqual(rot(t => ({ p: t >= 590 ? TOP : BOT })), 1);
    assert.strictEqual(rot(t => ({ p: t >= 591 ? TOP : BOT })), 0);
    // A death closes the run: 6 s top, dead 20 s, then 6 s top again.
    const died = t => (t < 400 ? { p: BOT } : t < 406 ? { p: TOP } : t < 426 ? null : t < 432 ? { p: TOP, deaths: 1 } : { p: BOT, deaths: 1 });
    assert.strictEqual(rot(died), 0);
    // No home lane (always in the jungle): none.
    assert.strictEqual(rot(t => ({ p: t >= 400 && t < 420 ? TOP : JUNGLE })), 0);
});

test('lane exit is the first minute from 5:00 with under half of the next minute in the home lane', () => {
    const exit = (at, to = 900) => seriesOf(game([bot(0, 2, at, 0, to)]))[0].lane_exit;
    assert.strictEqual(exit(t => ({ p: t < 480 ? BOT : JUNGLE })), 480);
    assert.strictEqual(exit(() => ({ p: BOT })), undefined);
    // A 40 s base trip in the 6:00 minute is not a lane exit.
    assert.strictEqual(exit(t => ({ p: t >= 360 && t < 400 ? BASE : BOT })), undefined);
    // 30 of 60 s in lane is half, not under half; 29 is under.
    assert.strictEqual(exit(t => ({ p: t >= 420 && t < 450 ? JUNGLE : BOT })), undefined);
    assert.strictEqual(exit(t => ({ p: t >= 420 && t < 451 ? JUNGLE : BOT })), 420);
    // The minute must end by `end`: last snapshot 15:59 gives end 15:00, so leaving at 15:00 is not read; at 14:01 it is.
    assert.strictEqual(exit(t => ({ p: t < 900 ? BOT : JUNGLE }), 959), undefined);
    assert.strictEqual(exit(t => ({ p: t < 841 ? BOT : JUNGLE })), 840);
});

test('a teleport-sized jump landing by an ally is a TP join; a respawn or a TP to base is not', () => {
    const joins = (...bots) => seriesOf(game(bots))[0].tp_joins;
    const ally = bot(1, 2, () => ({ p: TOP }), 600, 760);
    assert.strictEqual(joins(bot(0, 2, t => ({ p: t < 650 ? BOT : TOP }), 600, 760), ally), 1);
    // No ally at the landing; an enemy there does not count.
    assert.strictEqual(joins(bot(0, 2, t => ({ p: t < 650 ? BOT : TOP }), 600, 760), bot(5, 3, () => ({ p: TOP }), 600, 760)), 0);
    // Two jumps 3 s apart both count; a jump back 2 s later is the same jump.
    const bounce = d => t => ({ p: t < 650 ? BOT : t < 650 + d ? TOP : BOT });
    const allyBoth = bot(1, 2, t => ({ p: t < 650 ? TOP : BOT }), 600, 760);
    assert.strictEqual(joins(bot(0, 2, bounce(3), 600, 760), allyBoth), 1);
    assert.strictEqual(joins(bot(0, 2, t => ({ p: t < 650 ? BOT : t < 653 ? TOP : BOT }), 600, 760), bot(1, 2, t => ({ p: t < 653 ? TOP : BOT }), 600, 760)), 2);
    // Dies on bot at 640, respawns at 660 in fountain next to an ally standing there.
    const inFountain = bot(1, 2, () => ({ p: FOUNTAIN }), 600, 760);
    assert.strictEqual(joins(bot(0, 2, t => (t <= 640 ? { p: BOT } : t < 660 ? null : { p: FOUNTAIN, deaths: 1 }), 600, 760), inFountain), 0);
    assert.strictEqual(joins(bot(0, 2, t => ({ p: t < 650 ? TOP : FOUNTAIN }), 600, 760), inFountain), 0);
    // Before 10:00 is not read.
    assert.strictEqual(joins(bot(0, 2, t => ({ p: t < 550 ? BOT : TOP }), 500, 760), bot(1, 2, () => ({ p: TOP }), 500, 760)), 0);
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

test('ally steals: n defaults to 1, only before 10:00, the support and the core alive and within 700, per team', () => {
    // Radiant as above: support 3 is 300 units from safe-lane core 1; support 4 stands 800 from off-lane core 2.
    // Support 3 is dead 300-320; core 1 is dead 450-470 (both respawn in place with deaths=1).
    const gone = (a, b) => t => t > a && t < b;
    const rad = [
        bot(0, 2, t => ({ p: MID, lh: Math.floor(t / 10) })),
        bot(1, 2, t => (gone(450, 470)(t) ? null : { p: BOT, lh: Math.floor(t / 8), deaths: t >= 470 ? 1 : 0 })),
        bot(2, 2, t => ({ p: TOP, lh: Math.floor(t / 20) })),
        bot(3, 2, t => (gone(300, 320)(t) ? null : { p: [BOT[0] + 300, BOT[1]], lh: Math.floor(t / 60), deaths: t >= 320 ? 1 : 0 })),
        bot(4, 2, t => ({ p: [TOP[0], TOP[1] + 800], lh: Math.floor(t / 100) })),
    ];
    // Dire: mid 5, safe (top) 6, off (bot) 7; support 8 next to core 6, support 9 alone.
    const DT = [-128, 6016], DM = [524, 652], DB = [6269, -2240];
    const dire = [
        bot(5, 3, t => ({ p: DM, lh: Math.floor(t / 10) })),
        bot(6, 3, t => ({ p: DT, lh: Math.floor(t / 8) })),
        bot(7, 3, t => ({ p: DB, lh: Math.floor(t / 20) })),
        bot(8, 3, t => ({ p: [DT[0] + 200, DT[1]], lh: Math.floor(t / 60) })),
        bot(9, 3, t => ({ p: [DB[0], DB[1] + 2000], lh: Math.floor(t / 100) })),
    ];
    const lh = (t, pid, n) => ({ ev: 'lasthit', t, pid, ...(n === undefined ? {} : { n }) });
    const events = [
        lh(100, 3), lh(110, 3, 0), lh(120, 3, 3), lh(599.5, 3, 1), // 1 + 1 + 3 + 1
        lh(600, 3, 1), // 10:00 is not before 10:00
        lh(310, 3, 1), // the support is dead
        lh(460, 3, 1), // the only core near is dead
        lh(210, 4, 1), // core 800 away
        lh(200, 1, 1), // a core's own last hit
        lh(150, 8, 2), lh(160, 9, 1), // Dire: 2 next to its core, none alone
    ];
    const m = metricsOf(game([...rad, ...dire], events));
    assert.deepStrictEqual([m.roles.r4, m.roles.r5, m.roles.d4, m.roles.d5], ['h3', 'h4', 'h8', 'h9']);
    assert.deepStrictEqual(m.ally_creep_steals, { 2: 6, 3: 2 });
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

// World events (slice 23), through the log store (@dynamic_world).
const ev = (name, t, f) => ({ ev: name, t, ...f });

/** worldMetrics of the game through the log store, with `role` pid -> position. */
function worldOf(g, role = {}) {
    const { store, file } = stored(g);
    try {
        return D.worldMetrics(store, file, 1, D.heroes(store, file, 1), role);
    } finally {
        store.db.close();
    }
}

test('world metrics: rune shares by the mid, sentries, smokes merged, events absent read undefined', () => {
    const bots = [bot(1, 2, () => ({ p: MID }), 0, 800), bot(2, 2, () => ({ p: BOT }), 0, 800), bot(6, 3, () => ({ p: [6000, 6000] }), 0, 800)];
    const role = { 1: 2, 2: 4, 6: 2 };
    const events = [
        ev('rune_pickup', 120, { pid: 1, team: 2, kind: 'water' }),
        ev('rune_pickup', 240, { pid: 2, team: 2, kind: 'water' }),
        ev('rune_pickup', 360, { pid: 1, team: 2, kind: 'power' }),
        ev('rune_pickup', 370, { pid: 1, team: 2, kind: 'bounty' }),
        ev('ward_place', 50, { pid: 2, team: 2, kind: 'sentry' }),
        ev('ward_place', 40, { pid: 2, team: 2, kind: 'obs' }),
        ev('ward_place', 95, { pid: 6, team: 3, kind: 'sentry' }),
        ev('ward_place', 60, { pid: 2, team: 2, kind: 'sentry' }),
        ev('smoke_use', 500, { pid: 1, team: 2 }),
        ev('smoke_use', 501, { pid: 2, team: 2 }),
        ev('smoke_use', 600, { pid: 1, team: 2 }),
        ev('smoke_use', 602, { pid: 2, team: 2 }),
        ev('smoke_use', 604, { pid: 1, team: 2 }),
        ev('smoke_use', -50, { pid: 1, team: 2 }),
    ];
    const m = worldOf(game(bots, events), role);
    assert.strictEqual(m.mid_water_rune_pct[2], 0.5);
    assert.strictEqual(m.mid_power_rune_pct[2], 1);
    assert.strictEqual(m.mid_power_rune_pct[3], undefined);
    assert.strictEqual(m.power_rune_pickups[2], 1);
    assert.deepStrictEqual(m.first_sentry_time, { r4: 50 }, "the support's first sentry; pid 6 (role 2) is no support");
    assert.deepStrictEqual(m.sentry_by_90s, { 2: 1, 3: 0 }, 'a sentry at 1:35 is not by 1:30');
    // 500/501 one group; 600/602 one group; 604 is 4 s after its group's first, so a new one; the pregame smoke is not counted.
    assert.deepStrictEqual(m.smoke_uses_per_team, { 2: 3, 3: 0 });
    const none = worldOf(game(bots, []), role);
    assert.strictEqual(none.mid_power_rune_pct, undefined);
    assert.strictEqual(none.first_sentry_time, undefined);
    assert.strictEqual(none.first_t1_time, undefined);
    assert.strictEqual(none.towers_after_roshan_240, undefined);
});

test('world metrics: tp joins need distance, the 10:00-30:00 window and an ally at the landing', () => {
    const bots = [bot(1, 2, () => ({ p: MID }), 0, 1900), bot(2, 2, () => ({ p: BOT }), 0, 1900)];
    const tp = (t, x, y, d, pid = 2) => ev('tp', t, { pid, team: 2, x, y, dist: d });
    const joins = events => worldOf(game(bots, events)).tp_joins_per_team_ev[2];
    assert.strictEqual(joins([tp(700, MID[0] + 300, MID[1], 5000), tp(800, MID[0], MID[1], 500), tp(500, MID[0], MID[1], 5000), tp(900, 6000, 6000, 5000)]), 1);
    assert.strictEqual(joins([tp(700, MID[0] + 1201, MID[1], 5000)]), 0, 'landing 1201 from the ally');
    assert.strictEqual(joins([tp(1800, MID[0], MID[1], 5000)]), 0, '30:00 is outside the window');
    assert.strictEqual(joins([tp(700, MID[0], MID[1], 5000, 1)]), 0, 'the hero itself is no ally');
});

/** A Dire bot standing at [6000, 6000] to `to` that dies (no snapshots for 30 s) at each time in `dies`. */
const direDies = (pid, dies, to = 2000) =>
    bot(pid, 3, t => {
        if (dies.some(d => t > d && t < d + 30)) return null;
        return { p: [6000, 6000], deaths: dies.filter(d => t >= d + 30).length };
    }, 0, to);

test('world metrics: first T1, cash-in after a 3+ kill burst, Roshan de-duplicated and followed by a tower', () => {
    // Radiant kills three Dire heroes at 900-920; a Dire tower falls at 1000 (cash-in). A later burst at 1500 has no tower.
    const bots = [bot(1, 2, () => ({ p: MID }), 0, 2000), direDies(6, [900, 1500]), direDies(7, [910, 1505]), direDies(8, [920, 1510])];
    const events = [
        ev('building_fall', 700, { team: 2, kind: 'tower', tier: 2 }),
        ev('building_fall', 650, { team: 3, kind: 'tower', tier: 1 }),
        ev('building_fall', 1000, { team: 3, kind: 'tower', tier: 2 }),
        ev('roshan_kill', 1200, { team: 2, at: 1199.5 }),
        ev('roshan_kill', 1200.2, { team: 3, at: 1199.5 }),
        ev('aegis', 1203, { pid: 1, team: 2 }),
        ev('building_fall', 1300, { team: 2, kind: 'rax', id: 1 }),
        ev('building_fall', 1400, { team: 3, kind: 'tower', tier: 3 }),
        ev('roshan_kill', 1700, { team: 2, at: 1699 }), // a second kill, followed by no fall
    ];
    const m = worldOf(game(bots, events));
    assert.strictEqual(m.first_t1_time, 650);
    assert.strictEqual(m.cash_in_kills_pct[2], 0.5);
    assert.strictEqual(m.cash_in_kills_pct[3], undefined);
    assert.strictEqual(m.first_roshan_time, 1200);
    // Two kills (1200 and 1200.2 share `at`): the Radiant aegis team's own rax at 1300 does not count, the Dire tower at 1400
    // does; the kill at 1700 is followed by nothing.
    assert.strictEqual(m.towers_after_roshan_240, 0.5);
    // Without the Dire tower only the aegis team's own rax falls: the kill is not followed up.
    assert.strictEqual(worldOf(game(bots, events.filter(e => e.t !== 1400))).towers_after_roshan_240, 0);
    // With no aegis logged, any fall counts (the rax at 1300).
    assert.strictEqual(worldOf(game(bots, events.filter(e => e.t !== 1400 && e.ev !== 'aegis'))).towers_after_roshan_240, 0.5);
});

test('world metrics: three deaths at one second are one burst; 16 s apart they are not', () => {
    const fall = ev('building_fall', 1000, { team: 3, kind: 'tower', tier: 2 });
    const cash = (dies, f = fall) => worldOf(game([bot(1, 2, () => ({ p: MID }), 0, 2000), ...dies.map((d, i) => direDies(6 + i, [d]))], [f])).cash_in_kills_pct[2];
    assert.strictEqual(cash([900, 900, 900]), 1);
    assert.strictEqual(cash([900, 916, 932]), undefined, 'no burst');
    assert.strictEqual(cash([900, 905]), undefined, 'two deaths are no burst');
    assert.strictEqual(cash([900, 900, 900], { ...fall, t: 1020 }), 1, 'a fall 120 s after the burst cashes in');
    assert.strictEqual(cash([900, 900, 900], { ...fall, t: 1021 }), 0, '121 s is too late');
});

test('wisdom proxy: a hero 3 s within 300 of the shrine by fill + 15 s takes it', () => {
    const SH = [-7948, 768];
    // Takes the 7:00 fill at 7:10-7:13; reaches the 14:00 fill at 14:20 (too late).
    const at = t => ({ p: (t >= 430 && t < 433) || (t >= 860 && t < 870) ? [SH[0] + 100, SH[1]] : TOP });
    assert.deepStrictEqual(worldOf(game([bot(1, 2, at, 0, 900)])).wisdom_rune_taken_within_15s, { 2: 0.5, 3: 0 });
    // 2 s at the shrine is not a take.
    const short = t => ({ p: t >= 430 && t < 432 ? [SH[0] + 100, SH[1]] : TOP });
    assert.strictEqual(worldOf(game([bot(1, 2, short, 0, 900)])).wisdom_rune_taken_within_15s[2], 0);
    // Three seconds with a gap between them are not a channel.
    const gap = t => ({ p: [430, 432, 434].includes(t) ? [SH[0] + 100, SH[1]] : TOP });
    assert.strictEqual(worldOf(game([bot(1, 2, gap, 0, 900)])).wisdom_rune_taken_within_15s[2], 0);
    // A game ending before 7:15 has no fill to take.
    assert.deepStrictEqual(worldOf(game([bot(1, 2, at, 0, 400)])).wisdom_rune_taken_within_15s, { 2: undefined, 3: undefined });
});

/** stackAttempts of a log holding only the given ev=stack lines, through the log store. */
function stackOf(events, until) {
    const { store, file } = stored(game([], events.map(e => ({ ev: 'stack', ...e }))));
    try {
        return D.stackAttempts(store, file, 1, until);
    } finally {
        store.db.close();
    }
}

test('stackAttempts: one entry per ev=stack line before until; empty without any', () => {
    const line = (t, f) => ({ t, pid: 4, min: 3, ...f });
    const events = [
        line(242, { res: 'stacked', why: 'ok', camp: 15, type: 'small', aggro: 55.4, before: 3, after: 6, away: 12.8, death: 0 }),
        line(300, { min: 5, res: 'skip', why: 'enemy-near' }),
        line(480, { min: 7, res: 'failed', why: 'dead', away: 9, death: 1 }),
    ];
    const a = stackOf(events, 400);
    assert.deepStrictEqual(a.map(x => x.res), ['stacked', 'skip']);
    assert.deepStrictEqual([a[0].death, a[1].death], [false, false], 'a skip line has no death field: false, as before');
    assert.deepStrictEqual([a[0].camp, a[0].aggro, a[0].type, a[0].hitd], [15, 55.4, 'small', undefined]);
    assert.strictEqual(stackOf(events)[2].death, true, 'no until: every line');
    assert.strictEqual(stackOf(events, 480).length, 2, 'until is exclusive');
    const { store, file } = stored(game([bot(0, 2, () => ({ p: MID }), 0, 20)]));
    try {
        assert.deepStrictEqual(D.stackAttempts(store, file, 1, 600), [], 'a game without ev=stack (no ev_stack table at all)');
    } finally {
        store.db.close();
    }
});

test('stackAttempts: cause of a not-stacked attempt from the :59.5 sample', () => {
    const ns = f => ({ t: 245, pid: 4, min: 3, res: 'not_stacked', why: 'ok', before: 3, ...f });
    const cause = f => stackOf([ns(f)], 600)[0].cause;
    assert.strictEqual(cause({ box59: 0, bot59: 1, vis59: 1, after: 3 }), 'bot-in-box');
    assert.strictEqual(cause({ box59: 2, bot59: 0, vis59: 1, after: 3 }), 'camp-in-box');
    assert.strictEqual(cause({ box59: 0, bot59: 0, vis59: 0, after: '?' }), 'unseen');
    assert.strictEqual(cause({ box59: 0, bot59: 0, vis59: 1, after: 2 }), 'no-spawn');
    assert.strictEqual(cause({ box59: '?', after: 3 }), undefined);
    assert.strictEqual(stackOf([ns({ res: 'failed', why: 'dead' })], 600)[0].cause, 'dead');
    assert.strictEqual(stackOf([ns({ res: 'stacked', box59: 0 })], 600)[0].cause, undefined);
});

test('stackAttempts: left59 names the camp neutrals still in the box at :59.5 (user replay s4solo1)', () => {
    const left = n59 => stackOf([{ t: 245, pid: 2, min: 3, res: 'not_stacked', why: 'ok', ...(n59 === undefined ? {} : { n59 }) }], 600)[0].left59;
    assert.strictEqual(left('satyr_hellcaller:120:in:-,satyr_soulstealer:900:out:a,dead'), 'satyr_hellcaller:-');
    assert.strictEqual(left('ogre_mauler:900:out:a,ogre_magi:?'), '-');
    assert.strictEqual(left('?'), undefined);
    assert.strictEqual(left(undefined), undefined);
});

test('stackAttempts: lane carries the lane creeps near the camp after the hit (user, s4solo7ab: a pull)', () => {
    const one = e => stackOf([{ t: 245, pid: 2, min: 3, res: 'stacked', why: 'ok', ...e }], 600)[0].lane;
    assert.strictEqual(one({ lane: 4 }), 4);
    assert.strictEqual(one({}), undefined);
});

test('stackAttempts: idle carries the OHA idle relocations the job held (slice stack-hit; ER-007 read 0 without it)', () => {
    const one = e => stackOf([{ t: 245, pid: 2, min: 3, res: 'stacked', why: 'ok', ...e }], 600)[0].idle;
    assert.strictEqual(one({ idle: 3 }), 3);
    assert.strictEqual(one({}), undefined);
});
