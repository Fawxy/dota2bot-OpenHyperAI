'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { readGames, checkOne, factsOf, worldOf } = require('../cut');
const { fromTrade, fromKeep, diffRows } = require('../trade_diff');

const hev = (s) => `11/19 15:33:39 [VScript] [HEV] ${s}`;
const cutOf = (line) => {
    const g = readGames([hev('t=-90.000 ev=bot pid=1 team=2 ours=Trade:1'), hev(line)].join('\n')).pop();
    return { g, cut: g.cuts[0] };
};

// kind=trade2: the cut carries every input of Trade.Decide, and the driver replays it through the built Lua.
const BASE = 't=200.000 ev=cut pid=1 kind=trade2 role=core hp=1 bu=0.2 n=1 mi=0 tm=0 hc=0 cr=1 dn=0';
const FAVOURED = 'cd="7,0.7,420,300,100,0,1,0,0,0.3,0.2,0,0,-,-,-,-,-,-"';

test('trade2: a cut replays the answer the game logged, and an end beside it', () => {
    const hit = cutOf(`${BASE} ${FAVOURED} lv=hit tgt=7 how=attack:free why=hit`);
    assert.deepStrictEqual([checkOne(hit.g, hit.cut).same, checkOne(hit.g, hit.cut).got], [true, 'hit(hero#7)']);
    const burst = cutOf(`${BASE.replace('bu=0.2', 'bu=1.2')} ${FAVOURED} lv=none why=burst`);
    assert.strictEqual(checkOne(burst.g, burst.cut).got, 'none(burst)');
    assert.ok(checkOne(burst.g, burst.cut).same);
    const run = cutOf(`${BASE} ${FAVOURED} run=hit:7:-:1:2:1.5:1:0.06:0:-:-:-:-:- lv=none why=losing ed=losing`);
    const r = checkOne(run.g, run.cut);
    assert.deepStrictEqual([r.same, r.got], [true, 'none(losing)/end(losing)']);
    const wrong = cutOf(`${BASE} ${FAVOURED} lv=kill tgt=7 why=kill`);
    assert.strictEqual(checkOne(wrong.g, wrong.cut).same, false);
});

test('trade2: the pair, a candidate walk read and a catch read ride on the line', () => {
    const cd = 'cd="7,0.2,120,300,100,0,1,0,0,0.2,0.3,0,0,0.1,1,0.6,1,500,30"';
    const missing = cutOf(`${BASE} ${cd} lv=none why=missing`);
    assert.strictEqual(checkOne(missing.g, missing.cut).got, 'none(missing)');
    const join = cutOf(`${BASE} cd="7,0.7,420,300,100,0,1,0,0,0.2,0.3,0,0,-,-,-,-,-,-" pjr=join:7:0.5:0.2 lv=join tgt=7 why=pair`);
    assert.strictEqual(checkOne(join.g, join.cut).got, 'join(hero#7)');
    assert.match(factsOf(worldOf(join.g, join.cut)).join('\n'), /candidate pid 7: HP 70%/);
});

// trade_diff: an old line mapped into Inputs and the new Decide's answer against the old one.
const oldTrade = (extra) => fromTrade(readGames([hev(`t=200.000 ev=cut pid=1 kind=trade role=core tgt=6 hp=1 thp=0.7 en=2 ally=1 cr=1 hc=0 tw=0 kh=0.4 lf=1 d=300 rch=698 hl=48 ms=300 tms=300 aw=0 lw=1 tlh=0 bu=0.2 tm=0 ar=150 tar=150 ko=0.3 kt=0.2 tf=1 dn=0 ${extra}`)].join('\n')).pop().cuts[0]);

test('trade_diff: outnumbered is no longer a refusal; a lost trade with the same answer is not a difference', () => {
    const rows = [oldTrade('dec=outnumbered'), oldTrade('dec=trade')];
    const { groups, counts } = diffRows(rows);
    assert.deepStrictEqual(groups.map((g) => [g.old, g.new, g.n]), [['none:outnumbered', 'hit', 1]]);
    assert.deepStrictEqual([counts.trade.same, counts.trade.differ], [1, 1]);
});

test('trade_diff: a kill candidate whose answer depends on the catch read is not replayable, not a difference', () => {
    const row = fromTrade(readGames([hev('t=200.000 ev=cut pid=1 kind=trade role=core tgt=6 hp=1 thp=0.2 en=1 ally=1 cr=1 hc=0 tw=0 kh=0.4 lf=1 d=300 rch=698 hl=48 aw=0 lw=1 tlh=0 bu=0.2 tm=0 ar=150 tar=150 ko=0.2 kt=0.3 dn=0 dec=kill')].join('\n')).pop().cuts[0]);
    const { groups, counts } = diffRows([row]);
    assert.deepStrictEqual([groups.length, counts.trade.notReplayable, counts.trade.differ], [0, 1, 0]);
});

test('trade_diff: a kill that failed one catch read ended in the old rule and keeps in the new', () => {
    const keep = (extra) => fromKeep(readGames([hev(`t=200.000 ev=cut pid=1 kind=keep role=core tgt=6 ek=kill alv=1 sn=1 oa=2 sa=1.5 kh=0.4 hp=1 thp=0.2 en=1 ally=1 cr=0 hc=0 tw=0 bu=0.1 tm=0 d=300 ar=150 hl=48 cth=100 csf=3 chu=300,198,100,10, ${extra}`)].join('\n')).pop().cuts[0]);
    const { groups } = diffRows([keep('dec=cannot_catch'), keep('dec=keep')]);
    assert.deepStrictEqual(groups.map((g) => [g.old, g.new, g.n]), [['end:cannot_catch', 'keep', 1]]);
});
