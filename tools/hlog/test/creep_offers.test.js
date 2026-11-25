'use strict';
// The lane creep offer's lines joined to their creep's death (queries/creep_offers.sql, creep_offer_cells.sql, creep_offer_grades.sql,
// fragment creep_offer_rows). A synthetic unit_seen game: Radiant sniper (pid 0, pos 2) and Dire zuus (pid 5, pos 2). Each team numbers its
// creeps itself, so a theirs creep's cid on the hero's line is the taker's creep_death cid, never the owner's unit_gone cid:
// L1 100.3   o  melee  sniper denies its own creep (unit_gone cid 1 by 0)                   deny, nobody, mine
//    decoys numbered 1 and nearer in time: a Dire creep's own cid 1 (100.25) and Radiant's creep_death cid 1 on a Dire creep (100.2)
// L2 200.3   t  melee  sniper's last hit: creep_death cid 41; the owner's own cid is 2, and a Dire creep numbered 41 dies at 300
// L3 250.3   t  melee  no creep_death for it: only Dire's unit_gone (cid 3) 0.3 s earlier near the sniper   owner-side fallback
// L4 300.3   t  ranged no ranged death near                                                  unmatched
// L5 130.3   o  melee  its creep dies 19.7 s after the line (left the lists alive)           unmatched
// L6 400.3   zuus  t  ranged: its last hit on Radiant's creep (creep_death cid 9, team 3)     lh, us
// L7 500.3   o  melee  Dire's last hit on a Radiant creep (creep_death team 3 by 5)           lh, them
// L8 550.3   t  melee  Dire's zuus denies its own creep (owner's unit_gone by 5; no creep_death) deny, nobody, by 5 (owner fallback)
// L9 560.3   t  melee  a Dire creep the sniper's tower kills (creep_death tw=1, no hero)         tower, nobody; want 1 and read 1.1 s late
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const seen = (t, team, cid, type, x = 0) => line(t, `unit_seen team=${team} cid=${cid} kind=lane type=${type} lane=mid x=${x} y=0`);
const gone = (t, team, cid, by = 'none', x = 0) => line(t, `unit_gone team=${team} cid=${cid} x=${x} y=0 hp=0.1 by=${by}`);
const taker = (t, team, cid, by, kind, tw = 0) => line(t, `creep_death team=${team} kind=${kind} x=0 y=0 hp=0.05 by=${by} tw=${tw} cid=${cid}`);
const snap = (t, pid, x) => line(t, `snap pid=${pid} x=${x} y=0 alive=1 hp=90 ar=550`);
const offer = (t, pid, o) => line(t, `choice pid=${pid} kind=creep go=0 want=${o.want ?? 1} why=off src=shadow lane=2 slot=${o.slot ?? 0} cid=${o.cid} ck=${o.ck} who=${o.who}` +
    `${o.want === 0 ? '' : ` wo=${o.wo} wl=1`} walk=${o.walk} due=${o.due ?? 1} dies=${o.dies ?? 2} slk=1 hpp=1 mode=laning crhp=100 g2=0 g2r=0 pc=3 pd=63 ptw=0 ` +
    `eh=${o.eh ?? 0} exs=0 en=2:800:550:52:1.27:0 kb=${o.kb} md=${o.md ?? 60} ed=${o.ed ?? 0} ein=${o.ein ?? 0} atk=1${o.ra === undefined ? '' : ` ra=${o.ra}`}${o.h ? ` hh=${o.h[0]} sh=${o.h[1]} ch=${o.h[2]} enh=2:3` : ''}`);

const melee = (team) => `creep_${team === 2 ? 'goodguys' : 'badguys'}_melee`;
const ranged = (team) => `creep_${team === 2 ? 'goodguys' : 'badguys'}_ranged`;

function gameLines() {
    return [
        line(-90, 'bot pid=0 hero=sniper team=2 pos=2'),
        line(-90, 'bot pid=5 hero=zuus team=3 pos=2'),
        seen(60, 2, 1, melee(2)), seen(60, 2, 5, melee(2)), seen(60, 2, 6, melee(2)), seen(60, 2, 33, ranged(2)),
        seen(60, 3, 2, melee(3)), seen(60, 3, 3, melee(3), 100), seen(60, 3, 41, melee(3)), seen(60, 3, 1, melee(3)), seen(60, 3, 4, melee(3)), seen(60, 3, 8, melee(3)), seen(60, 3, 10, melee(3)),
        gone(100.25, 3, 1), gone(100.2, 3, 4), taker(100.2, 2, 1, 'none', 'melee'),
        gone(100, 2, 1, 0), offer(100.3, 0, { cid: 1, ck: 'm', who: 'o', walk: 0, want: 0, kb: 'none' }),
        offer(130.3, 0, { cid: 5, ck: 'm', who: 'o', walk: 2.5, want: 0, kb: 'tower' }), gone(150, 2, 5),
        gone(200, 3, 2), taker(200, 2, 41, 0, 'melee'),
        offer(200.3, 0, { cid: 41, ck: 'm', who: 't', walk: 0, slot: 197.5, wo: 0.1, dies: 2, kb: 'me', eh: 1, ra: 550, h: [1, 1, 2] }),
        snap(249.5, 0, -200), gone(250, 3, 3, 'none', 100),
        offer(250.3, 0, { cid: 77, ck: 'm', who: 't', walk: 0.6, slot: 248, wo: 0.2, dies: 1, due: 1.9, kb: 'foe', ein: 2, ed: 70, md: 60, ra: 550, h: [1, 1, 2] }),
        gone(300, 3, 41),
        offer(300.3, 0, { cid: 78, ck: 'r', who: 't', walk: 1.4, want: 0, kb: 'none', ra: 550, h: [2, 2, 2] }),
        gone(400, 2, 33), taker(400, 3, 9, 5, 'ranged'),
        offer(400.3, 5, { cid: 9, ck: 'r', who: 't', walk: 0, slot: 398, wo: 0.2, dies: 1.5, due: 2.5, kb: 'creep', ra: 600, h: [2, 2, 2] }),
        gone(500, 2, 6), taker(500, 3, 99, 5, 'melee'),
        offer(500.3, 0, { cid: 6, ck: 'm', who: 'o', walk: 0, want: 0, kb: 'foe' }),
        snap(549.5, 0, -200), gone(550, 3, 8, 5), offer(550.3, 0, { cid: 88, ck: 'm', who: 't', walk: 0, want: 0, kb: 'none', ra: 550 }),
        gone(560, 3, 10), taker(560, 2, 55, 'none', 'melee', 1),
        offer(560.3, 0, { cid: 55, ck: 'm', who: 't', walk: 0, slot: 558, wo: 0.1, dies: 3, due: 2.5, kb: 'tower', ra: 150, h: [3, 3, 2] }),
    ];
}

function load(extra = []) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-creep-offers-'));
    const file = path.join(dir, '2026-11-25T00-00-00-co_A_off_1.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(file, gameLines().concat(extra).sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}
const sqlOf = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');
const like = '%co_A_off_1%';

test('creep_offers: each line joins the death of its creep by the logging team\'s own cid', () => {
    const rows = load().query(sqlOf('creep_offers'), { like }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.pid, r.t, r.cid, r.matched, r.src, r.dt, r.how, r.paid, r.by_pid, r.mine]), [
        [0, 100.3, 1, 1, 'cid', 100, 'deny', 'nobody', 0, 1],
        [0, 130.3, 5, 0, null, null, null, null, null, 0],
        [0, 200.3, 41, 1, 'cid', 200, 'lh', 'us', 0, 1],
        [0, 250.3, 77, 1, 'owner', 250, 'other', 'nobody', null, 0],
        [0, 300.3, 78, 0, null, null, null, null, null, 0],
        [5, 400.3, 9, 1, 'cid', 400, 'lh', 'us', 5, 1],
        [0, 500.3, 6, 1, 'cid', 500, 'lh', 'them', 5, 0],
        [0, 550.3, 88, 1, 'owner', 550, 'deny', 'nobody', 5, 0],
        [0, 560.3, 55, 1, 'cid', 560, 'tower', 'nobody', null, 0],
    ]);
    assert.deepStrictEqual(rows.map(r => [r.inrange, r.outdmg, r.covered, r.snap]), [
        [1, 0, 0, null], [0, 0, 0, null], [1, 0, 1, 197.6], [0, 1, 0, 248.2], [0, 0, 0, null], [1, 0, 0, 398.2], [1, 0, 0, null], [1, 0, 0, null], [1, 0, 0, 558.1],
    ]);
    assert.deepStrictEqual(rows.map(r => [r.hero, r.team, r.pos]).slice(5, 6), [['zuus', 3, 2]]);
});

test('creep_offers: the window decides a death, and filters are comma lists', () => {
    const store = load();
    const wide = store.query(sqlOf('creep_offers'), { like, fwd: 25 }).map(r => ({ ...r }));
    assert.deepStrictEqual(wide.filter(r => r.cid === 5).map(r => [r.matched, r.dt]), [[1, 150]], 'a creep dying 19.7 s after its line joins with a wider window');
    assert.deepStrictEqual(store.query(sqlOf('creep_offers'), { like, ck: 'r', who: 't' }).map(r => r.cid), [78, 9]);
    assert.deepStrictEqual(store.query(sqlOf('creep_offers'), { like, hero: 'zuus' }).map(r => r.cid), [9]);
});

test('creep_offers: the creep row\'s own lines (src=own) are read beside the shadow\'s, with the decision; another src is not', () => {
    const own = (t, cid, rest) => line(t, `choice pid=5 kind=creep ${rest} lane=2 slot=${t - 2} cid=${cid} ck=r who=t wo=0 wl=1 walk=1.2 due=1.5 dies=3 slk=1 ` +
        'hpp=1 mode=laning crhp=100 g2=0 g2r=0 pc=1 pd=20 ptw=0 eh=0 exs=0 en= kb=none md=60 ed=0 ein=0 atk=0 erc=1 ert=0.4 otw=0');
    const rows = load([
        own(600.3, 91, 'go=1 want=1 src=own gat=0.6 gw=1.2'),
        own(610.3, 92, 'go=0 want=1 why=race src=own'),
        own(620.3, 93, 'go=0 want=1 why=off src=ping'),
    ]).query(sqlOf('creep_offers'), { like, from: 590, until: 700 }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.cid, r.csrc, r.go, r.why, r.gat, r.gw, r.erc, r.ert]), [
        [91, 'own', 1, null, 0.6, 1.2, 1, 0.4],
        [92, 'own', 0, 'race', null, null, 1, 0.4],
    ]);
});

test('creep_offer_cells: the counts of a cell, and the fate split by walk', () => {
    const rows = load().query(sqlOf('creep_offer_cells'), { like }).map(r => ({ ...r }));
    const cell = (pid, ck, who) => rows.find(r => r.pid === pid && r.ck === ck && r.who === who);
    const cols = r => [r.n, r.n_in, r.n_wk, r.med_wk, r.covered, r.outdmg, r.atk, r.mine, r.deny, r.us, r.them, r.nobody, r.unm,
        r.in_us, r.in_them, r.in_nobody, r.in_unm, r.in_deny, r.wk_us, r.wk_them, r.wk_nobody, r.wk_unm, r.wk_deny];
    assert.deepStrictEqual(cols(cell(0, 'm', 'o')), [3, 2, 1, 2.5, 0, 0, 3, 1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0]);
    assert.deepStrictEqual(cols(cell(0, 'm', 't')), [4, 3, 1, 0.6, 1, 1, 4, 1, 1, 1, 0, 3, 0, 1, 0, 2, 0, 1, 0, 0, 1, 0, 0],
        'their deny is in nobody and in deny, apart from the tower kill beside it');
    assert.deepStrictEqual(cols(cell(0, 'r', 't')), [1, 0, 1, 1.4, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]);
    assert.deepStrictEqual(cols(cell(5, 'r', 't')), [1, 1, 0, null, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    assert.strictEqual(rows.length, 4);
    const ranged = load().query(sqlOf('creep_offer_cells'), { like, ck: 'r' }).map(r => [r.pid, r.n]);
    assert.deepStrictEqual(ranged, [[0, 1], [5, 1]]);
});

test('creep_offer_grades: dies only where no hero hit, due against every death by fate class, and the forecast killer against the fate', () => {
    const rows = load().query(sqlOf('creep_offer_grades'), { like }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.filter(r => r.part === 'dies').map(r => [r.key, r.n, r.q1, r.med, r.q3, r.early, r.early5]),
        [['other', 1, 0.8, 0.8, 0.8, null, null], ['tower', 1, -1.1, -1.1, -1.1, null, null]],
        'the sniper\'s last hit and zuus\'s are not graded against dies');
    assert.deepStrictEqual(rows.filter(r => r.part === 'due').map(r => [r.key, r.n, r.q1, r.med, r.q3, r.early, r.early5]), [
        ['hero', 2, -0.7, 0.35, 1.4, 1, 1], ['other', 1, -0.1, -0.1, -0.1, 1, 0], ['tower', 1, -0.6, -0.6, -0.6, 1, 1],
    ]);
    assert.deepStrictEqual(rows.filter(r => r.part === 'killer').map(r => [r.key, r.fate, r.n]), [
        ['creep', 'me', 1], ['foe', 'foe', 1], ['foe', 'other', 1], ['me', 'me', 1], ['none', 'foe', 1], ['none', 'me', 1],
        ['none', 'unmatched', 1], ['tower', 'other', 1], ['tower', 'unmatched', 1],
    ]);
});

test('creep_offer_height: their creeps by projectile and by the stand spot against the creep, and how many attacked ones were taken', () => {
    const store = load();
    const rows = store.query(sqlOf('creep_offer_height'), { like }).map(r => [r.proj, r.spot, r.n, r.atk, r.took, r.took_pct]);
    assert.deepStrictEqual(rows, [
        [1, 'below', 2, 2, 1, 50],
        [1, 'level', 2, 2, 1, 50],
        [1, 'unknown', 1, 1, 0, 0],
        [0, 'above', 1, 1, 0, 0],
    ]);
    const cols = store.query(sqlOf('creep_offers'), { like }).map(r => ({ ...r })).find(r => r.cid === 41);
    assert.deepStrictEqual([cols.hh, cols.sh, cols.ch, cols.ra, cols.enh, cols.up, cols.proj], [1, 1, 2, 550, '2:3', 1, 1]);
});
