'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { score, retreatRuns, trips, laneScore, creepFates, C } = require('../lane_score');

// Points on the mid lane, the Radiant fountain and Dire's mid tier 1 (dynamic.js TOWERS).
const MID = [0, 0];
const MID_R = [-1200, -1200]; // Radiant's side of mid, still in the lane
const R_FOUNT = [-6850, -6461];
const D_MID_T1 = [524, 652];

const snap = (s, o) => ({ s, x: MID[0], y: MID[1], alive: 1, hp: 100, lvl: 1, lh: 0, dn: 0, nw: 600, deaths: 0, hit: 0, ah: 0, tgt: null, ...o });
function series(from, to, f) {
    const out = [];
    for (let s = from; s <= to; s++) out.push(snap(s, f ? f(s) : {}));
    return out;
}
function facts(heroSeries, extra = {}) {
    const heroes = [], secs = [];
    for (const [pid, team, pos, side, ser] of heroSeries) {
        heroes.push({ pid, team, pos, side });
        for (const r of ser) secs.push({ pid, ...r });
    }
    return { label: 't', game_id: 1, heroes, secs, loss: [], fates: [], fronts: [], ...extra };
}
const row = (rows, pid, at) => rows.find((r) => r.pid === pid && r.at === at);

test('lane and opponent: the same kind in the same lane wins over a nearer hero of the other kind', () => {
    const rows = score(facts([
        [2, 2, 2, 'ours', series(0, 300)],
        [7, 3, 2, 'oha', series(0, 300, () => ({ x: 200 }))],        // core, a little away
        [9, 3, 5, 'oha', series(0, 300)],                             // support, on top of us
        [8, 3, 1, 'oha', series(0, 300, () => ({ x: -6000, y: 5800 }))], // top lane
    ]), [300]);
    const r = row(rows, 2, 300);
    assert.strictEqual(r.lane, 'mid');
    assert.strictEqual(r.opp, 7);
    assert.strictEqual(row(rows, 8, 300).opp, null);
});

test('levels: the gap at T and the first second two levels behind', () => {
    const rows = score(facts([
        [2, 2, 2, 'ours', series(0, 300, (s) => ({ lvl: s < 200 ? 2 : 3 }))],
        [7, 3, 2, 'oha', series(0, 300, (s) => ({ lvl: s < 150 ? 3 : s < 250 ? 4 : 5 }))],
    ]), [120, 300]);
    assert.strictEqual(row(rows, 2, 120).behind2, null);
    assert.strictEqual(row(rows, 2, 300).behind2, 150);
    assert.deepStrictEqual([row(rows, 2, 120).fell2, row(rows, 2, 300).fell2], [0, 1]);
    assert.strictEqual(row(rows, 2, 300).lvl_gap, 2);
    assert.strictEqual(row(rows, 7, 300).lvl_gap, -2);
});

test('attacking and attacked seconds, and HP lost split among a second\'s sources', () => {
    const rows = score(facts([
        [2, 2, 2, 'ours', series(0, 100, (s) => ({ tgt: s < 10 ? 'npc_dota_hero_sniper' : s < 15 ? 'npc_dota_creep_badguys_melee' : null, ah: s >= 50 && s < 53 ? 1 : 0 }))],
        [7, 3, 2, 'oha', series(0, 100)],
    ], { loss: [
        { pid: 2, t: 20, died: 0, loss: 10, src: 'hero' },
        { pid: 2, t: 21, died: 0, loss: 6, src: 'hero+creep' },
        { pid: 2, t: 22, died: 0, loss: 4, src: 'tower?' },
        { pid: 2, t: 23, died: 0, loss: 2, src: 'unexplained' },
        { pid: 2, t: 24, died: 1, loss: 50, src: 'hero' },
    ] }), [100]);
    const r = row(rows, 2, 100);
    assert.deepStrictEqual([r.att_s, r.attd_s], [10, 3]);
    assert.deepStrictEqual([r.hpl_hero, r.hpl_creep, r.hpl_tower, r.hpl_other], [13, 3, 4, 2]);
});

test('retreat runs: classes in order, and a step out shorter than RUN_MIN is no run', () => {
    // Walk 300 a second towards the Radiant fountain along the diagonal from mid.
    const toward = (x0, n) => Array.from({ length: n }, (_, i) => [x0 - 212 * i, x0 - 212 * i]);
    const mk = (pts, t0, o) => pts.map(([x, y], i) => snap(t0 + i, { x, y, ...(typeof o === 'function' ? o(i) : o) }));
    const loss = () => 0;
    const hit = mk(toward(0, 5), 10, (i) => ({ hit: i === 0 ? 1 : 0 }));
    const low = mk(toward(0, 5), 10, { hp: 40 });
    const fresh = mk(toward(0, 5), 10, { hp: 95 });
    const short = mk(toward(0, 3), 10, {});
    const home = mk(toward(-4400, 8), 10, {});
    assert.deepStrictEqual(retreatRuns(2, hit, loss).map((r) => [r.cls, r.secs]), [['after_hit', 4]]);
    assert.deepStrictEqual(retreatRuns(2, low, loss).map((r) => r.cls), ['low_hp']);
    assert.deepStrictEqual(retreatRuns(2, fresh, loss).map((r) => r.cls), ['no_damage']);
    assert.deepStrictEqual(retreatRuns(2, fresh, () => 5).map((r) => r.cls), ['other']);
    assert.deepStrictEqual(retreatRuns(2, short, loss), []);
    assert.deepStrictEqual(retreatRuns(2, home, loss).map((r) => r.cls), ['fountain']);
    // A teleport (a jump over JUMP) is no run.
    assert.deepStrictEqual(retreatRuns(2, [snap(1, { x: 0, y: 0 }), snap(2, { x: -3000, y: -3000 })], loss), []);
});

test('trips home: departure from the lane, HP there, back in lane; a death ends the trip and a respawn is none', () => {
    const lane = (s, o) => ({ s, ...snap(s, { x: MID_R[0], y: MID_R[1], lane: 'mid', ...o }) });
    const base = (s, o) => ({ s, ...snap(s, { x: R_FOUNT[0], y: R_FOUNT[1], lane: 'base', ...o }) });
    const way = (s) => ({ s, ...snap(s, { x: -4000, y: -4000, lane: 'other' }) });
    const ser = [lane(10, { hp: 30, lh: 5 }), way(20), base(30), way(40), lane(60),
        lane(100), base(110, { deaths: 1 }), lane(130, { deaths: 1 })];
    const out = trips(2, 'mid', ser, 300);
    assert.deepStrictEqual(out.map((t) => [t.dep, t.back, t.hp, t.tp]), [[10, 60, 30, false]]);
    const tp = trips(2, 'mid', [lane(10), base(11)], 300);
    assert.deepStrictEqual(tp.map((t) => [t.dep, t.back, t.tp]), [[10, 300, true]]);
});

test('trip rows: opponent last hits gained while away', () => {
    const ours = [...series(0, 100, () => ({ x: MID_R[0], y: MID_R[1] })),
        ...series(101, 140, () => ({ x: R_FOUNT[0], y: R_FOUNT[1] })),
        ...series(141, 300, () => ({ x: MID_R[0], y: MID_R[1] }))];
    const rows = score(facts([
        [2, 2, 2, 'ours', ours],
        [7, 3, 2, 'oha', series(0, 300, (s) => ({ lh: Math.floor(s / 10) }))],
    ]), [300]);
    const r = row(rows, 2, 300);
    assert.deepStrictEqual([r.trips, r.trip_s, r.trip_hp, r.trip_opp_lh, r.trip_tp], [1, 41, 100, 4, 1]);
});

test('deaths with the level gap, pools and share, the wave under their tower and creeps their tower took', () => {
    const rows = score(facts([
        [2, 2, 2, 'ours', series(0, 300, (s) => ({ lh: s >= 200 ? 3 : 0, deaths: s >= 150 ? 1 : 0, lvl: 2 }))],
        [7, 3, 2, 'oha', series(0, 300, () => ({ lvl: 4 }))],
    ], {
        fates: [
            { t: 100, team: 2, side: 'enemy', fate: 'own_lh', x: 0, y: 0, tw: 0 },
            { t: 110, team: 2, side: 'enemy', fate: 'other', x: 0, y: 0, tw: 0 },
            { t: 120, team: 2, side: 'enemy', fate: 'other', x: -6000, y: 5800, tw: 0 }, // top lane: not ours
            { t: 130, team: 2, side: 'own', fate: 'lost', x: 0, y: 0, tw: null },
            { t: 140, team: 3, side: 'enemy', fate: 'other', x: 400, y: 500, tw: 1 },    // our creep, their tower
            { t: 141, team: 3, side: 'enemy', fate: 'own_lh', x: 400, y: 500, tw: 1 },   // their hero's last hit
        ],
        fronts: [
            { s: 50, team: 2, midx: -1000, midy: -1000 },
            { s: 51, team: 2, midx: D_MID_T1[0] - 300, midy: D_MID_T1[1] - 300 },
            { s: 52, team: 2, midx: D_MID_T1[0], midy: D_MID_T1[1] },
            { s: 52, team: 3, midx: D_MID_T1[0], midy: D_MID_T1[1] },
        ],
    }), [300]);
    const r = row(rows, 2, 300);
    assert.deepStrictEqual([r.deaths, r.deaths_gap], [1, 2]);
    assert.deepStrictEqual([r.pool, r.own_pool, r.lh, r.lh_share], [2, 1, 3, 1.5]);
    assert.deepStrictEqual([r.wave_tower_s, r.tower_took], [2, 1]);
    // An enemy hero's front at our tower is its wave, not ours.
    assert.strictEqual(row(rows, 7, 300).wave_tower_s, 0);
});

test('lane score from a stored log: side from the ours field, a row per hero and time', () => {
    const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
    const lines = [line(0, 'bot pid=2 hero=a team=2 pos=2 ours=Lane:1'), line(0, 'bot pid=7 hero=b team=3 pos=2 ours=Lane:0')];
    for (let s = 0; s <= 120; s++) {
        lines.push(line(s, `snap pid=2 x=-500 y=-500 alive=1 hp=100 lvl=1 lh=${Math.floor(s / 30)} dn=0 deaths=0 hit=0 ah=0`));
        lines.push(line(s, `snap pid=7 x=500 y=500 alive=1 hp=100 lvl=${s > 90 ? 3 : 1} lh=0 dn=0 deaths=0 hit=0 ah=0`));
    }
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lanescore-')), 'lanescore1.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const res = laneScore(s, ['lanescore1'], [60, 120]);
    s.db.close();
    assert.strictEqual(res.games.length, 1);
    const r = res.rows.find((x) => x.pid === 2 && x.at === 120);
    assert.deepStrictEqual([r.side, r.lane, r.opp, r.lh, r.behind2], ['ours', 'mid', 7, 4, 91]);
    assert.strictEqual(res.rows.find((x) => x.pid === 7).side, 'oha');
    assert.ok(C.BASE_R > 0);
});

test('creep fates from the base tables: last hit, a paired enemy deny, other; own deny and lost', () => {
    const out = creepFates([
        { t: 10, team: 2, kind: 'melee', x: 0, y: 0, by: '1', tw: 0 },
        { t: 20, team: 2, kind: 'melee', x: 0, y: 0, by: 'none', tw: 0 },
        { t: 30, team: 2, kind: 'melee', x: 0, y: 0, by: 'none', tw: 1 },
    ], [
        { t: 20.5, team: 3, kind: 'melee', x: 100, y: 100, by: '7' },
        { t: 30, team: 3, kind: 'ranged', x: 0, y: 0, by: '7' }, // another kind: no pair
        { t: 40, team: 2, kind: 'melee', x: 0, y: 0, by: 'none' },
    ]);
    assert.deepStrictEqual(out.map((f) => [f.side, f.fate]), [['enemy', 'own_lh'], ['enemy', 'enemy_deny'], ['enemy', 'other'],
        ['own', 'own_deny'], ['own', 'own_deny'], ['own', 'lost']]);
});
