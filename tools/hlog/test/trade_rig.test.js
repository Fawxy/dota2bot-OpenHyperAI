'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { reps, summary, rangeSeconds } = require('../trade_rig');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const N = 'lane-trade';

function store(lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-tr-'));
    const f = path.join(dir, 'drill_lane-trade_t.log');
    const at = (l) => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return s;
}

const snap = (t, pid, hv, hc = 0, hit = 0) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=${Math.round(hv / 6)} hv=${hv} ar=550 mode=laning lh=0 dn=0 d=0.3 deaths=0 hit=${hit} hc=${hc}`);
const trade = (t, f) => line(t, `trade pid=1 role=core lf=1 kind=trade tgt=7 ${f}`);
const atk = (t) => line(t, `drill ph=atk name=${N} pid=1 rep=1 tpid=7 d=500`);
const chit = (t, dmg = 9) => line(t, `drill ph=chit name=${N} pid=1 rep=1 dmg=${dmg}`);
const hhit = (t, dmg) => line(t, `drill ph=hhit name=${N} pid=1 rep=1 tpid=7 dmg=${dmg}`);

test('trade_rig: a trade is graded from its open on the rig truth; a late one and an untaken offer are apart', () => {
    const l = [
        line(0, 'bot pid=1 hero=sniper team=2 pos=2'), line(0, 'bot pid=7 hero=zuus team=3 pos=2'),
        line(0.5, `drill ph=role name=${N} pid=1 team=2 pos=2 role=cast`),
        line(60, `drill ph=rep name=${N} team=2 rep=1 input=on start=60 var=stand`),
        line(90, `drill ph=rep name=${N} team=2 rep=2 input=on start=90 var=lasthit`),
        line(120, `drill ph=rep name=${N} team=2 rep=3 input=on start=120 var=hitback`),
        line(62, `drill ph=ready name=${N} pid=1 rep=1 var=stand ok=1`),
        line(92, `drill ph=ready name=${N} pid=1 rep=2 var=lasthit ok=1`),
        // Rep 1: a trade 65-66.5 that steps out and fires nothing in it; the hero attacks at 68 and 69 (in 5 s, not in the trade),
        // two creep hits at 66 and 67 and one at 71 (past 5 s). Then a second trade 70-73 that fires at 70.6.
        trade(66.5, 'result=done why=no_clear dur=1.5 hpd=20 thpd=0 pr=0 so=1 ag=2'),
        atk(68), atk(69), chit(66), chit(67), chit(71),
        // In it the cast takes one creep attack (71, 9) and two of Zuus's (20 each, at 71.5 and 72.5); the hpd of 40 leaves -9 to the rest.
        trade(73, 'result=done why=creeps dur=3 hpd=40 thpd=60 ld=0.6 pr=1 so=0 ag=1 fa=order'),
        // Creeps dying in it: an enemy one 300 off untaken, one taken by the cast, one 900 off (out of reach); one of ours 100 off.
        line(72, 'creep_death team=2 kind=melee x=300 y=0 hp=40 by=none'), line(72.2, 'creep_death team=2 kind=melee x=200 y=0 hp=40 by=1'),
        line(72.4, 'creep_death team=2 kind=melee x=900 y=0 hp=40 by=none'), line(71, 'own_creep_death team=2 kind=melee x=100 y=0 hp=0.4 by=none'), atk(70.6), hhit(71.5, 20), hhit(72.5, 20),
        // An offer not taken inside rep 1.
        trade(80, 'result=lost why=lost dur=0 pr=0 so=0'),
        // Rep 2: a trade opening at 117, within 5 s of the rep's end (120): late. Rep 3 never ready: no row.
        trade(118, 'result=done why=done dur=1 hpd=0 thpd=0 pr=1 so=0 ag=0'),
        // And one 95-96 whose 5 s window holds the HP reset run at 98 (sent for 85, late): late too.
        trade(96, 'result=done why=deny dur=1 hpd=0 thpd=0 pr=1 so=0 ag=0'),
        `11/18 19:59:51 [DOTACTL] t=98 ev=cmd src=drill at=85 cmd="rig_hp_all 1" out="[RIG] hp_all share=1 n=10"`,
    ];
    for (let t = 59; t <= 130; t++) {
        // The cast loses 20 at 66 and 20 at 68; the target loses 50 at 71.
        // The drop at 66 under a creep's flag, the one at 68 under a hero's.
        l.push(snap(t, 1, t < 66 ? 600 : t < 68 ? 580 : 560, t === 66 ? 1 : 0, t === 68 ? 1 : 0));
        l.push(snap(t, 7, t < 71 ? 500 : 450));
    }
    const s = store(l);
    const r = reps(s, 'drill_lane-trade');
    s.db.close();
    assert.deepStrictEqual(r.reps.map((x) => [x.rep, x.var, x.trades, x.lost]), [[1, 'stand', 2, 1], [2, 'lasthit', 2, 0]]);
    const [a, b, d, c] = r.trades;
    assert.strictEqual(d.late, 1);
    assert.deepStrictEqual([a.hero, a.n, a.open, a.ordered, a.fired, a.first, a.a5, a.ch5, a.hp5, a.thp5, a.why, a.late],
        ['sniper', 1, 65, 0, 0, 3, 2, 2, 40, 0, 'no_clear', 0]);
    assert.deepStrictEqual([b.n, b.open, b.ordered, b.fired, b.first, b.a5, b.ch5, b.thp5], [2, 70, 1, 1, 0.6, 1, 1, 50]);
    // The first trade (65-66.5) holds the creep attack at 66 only; the second the one at 71 and both of Zuus's.
    assert.deepStrictEqual([a.hpc, a.hph, b.hpc, b.hph, b.hpo], [9, 0, 9, 40, -9]);
    // The first began with its step-out (so=1, no order: no fa in that line); the second with an order. Only the second saw deaths.
    assert.deepStrictEqual([a.sf, b.sf, a.ulh, a.udn, b.ulh, b.udn], [1, 0, 0, 0, 1, 1]);
    assert.deepStrictEqual(a.s5, { creeps: 20, hero: 20, both: 0, other: 0 });
    assert.strictEqual(c.late, 1);
    const sum = summary(r);
    assert.deepStrictEqual([sum['sniper stand'].ready, sum['sniper stand'].withTrade, sum['sniper stand'].trades, sum['sniper stand'].fired, sum['sniper stand'].lost], [1, 1, 2, 1, 1]);
    assert.deepStrictEqual([sum['sniper stand'].split.creeps, sum['sniper stand'].split.hero, sum['sniper stand'].creepsEnd], [18, 40, 50]);
    assert.deepStrictEqual([sum['sniper lasthit'].trades, sum['sniper lasthit'].late], [0, 2]);
});

test('trade_rig: in-range seconds are graded by time, with or without a trade', () => {
    // The cast (ar 550) at x along y=0; the enemy hero at x=580 throughout (a second enemy 2,000 off never counts).
    const o = (t, x, f = {}) => ({ t, x, y: 0, hp: 90, ar: 550, alive: 1, tid: null, mode: 'laning', ...f });
    const own = [
        o(10, 0, { tid: 'h7' }), // 580 off, within 598: on the hero
        o(11, 0, { tid: 'u12', mode: 'laning' }), // on a creep
        o(12, 0), o(13, 40, { mode: 'attack' }), // 12 steps 40 toward; 13 steps 40 away
        o(14, 0), o(15, 10), // 14 moves 10: idle; 15 has no next snapshot within 1.5 s: idle
        o(17, 0, { hp: 70, tid: 'h7' }), // under 75: not counted
        o(18, -200, { tid: 'h7' }), // 780 off: outside strict, inside +400, on the hero
        o(19, -600), // 1,180 off: outside both
        o(30, 0), // past the window
    ];
    const foe = (x) => [10, 11, 12, 13, 14, 15, 17, 18, 19, 30].map((t) => ({ t: t + 0.2, x, y: 0, alive: 1 }));
    const r = rangeSeconds(own, [[7, foe(580)], [8, foe(2600)]], 10, 20, [[9.5, 10.5], [12.5, 14.5]]);
    assert.deepStrictEqual([r.secs, r.hero, r.creep, r.toward, r.away, r.idle], [6, 1, 1, 1, 1, 2]);
    // 10 (on the hero) sits in the trade episode 9.5-10.5, 13 and 14 in 12.5-14.5.
    assert.deepStrictEqual([r.heroTrade, r.heroModes], [1, { 'laning (trade)': 1 }]);
    assert.deepStrictEqual(r.modes, { laning: 3, 'attack (trade)': 1, 'laning (trade)': 1 });
    assert.deepStrictEqual([r.wide, r.wideHero], [7, 2]);
    // A foe whose nearest snapshot is over a second off is no read: of 10-15 only 14 and 15 have one (at 14.8).
    assert.strictEqual(rangeSeconds(own, [[7, [{ t: 14.8, x: 580, y: 0, alive: 1 }]]], 10, 20).secs, 2);
});
