'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { parseLog } = require('../parse');
const { inputsOf, diffGame } = require('../sustain_diff');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
// The line test_sustain_gather.lua checks CutFields writes, with its answer changed.
// A step 2 line (the old danger inputs: bua, lb, the tree as d,enemyD), as banked logs before step 3 hold them.
const OLD = 'pid=0 kind=sustain hpa=300 hpm=600 mpa=100 mpm=300 it=0,tango,3,112,0,16,0,1,0,1 tr=300,-1 hr=0 bua=150 rc=1 lb=250 rl=0 ml=0 ss=-500,-500,2.5 gd=230 co=20 ho=40 idl=0 af=0';
const CUT = 'pid=0 kind=sustain hpa=300 hpm=600 mpa=100 mpm=300 it=0,tango,3,112,0,16,0,1,0,1,1;1,flask,1,400,0,10,1,0,0,0,1 tr=0.5,1,0 nd=2.5 hr=0 kill=300 sh=1 rc=1 rl=0 ml=0 ss=-500,-500,2.5 gd=230 co=20 shp=tango,90,336,0 ho=40 idl=0 af=0 als=1,300,2';

test('a cut line reads back into the Inputs it was written from', () => {
    const g = parseLog(line(100, `cut ${CUT} ak=none why=fine`))[0];
    const i = inputsOf(g.events[0]);
    assert.equal(i.hp, 300);
    assert.equal(i.hpMax, 600);
    assert.deepEqual(i.items[0], { slot: 0, name: 'tango', charges: 3, hp: 112, mp: 0, dur: 16, breaks: false, tree: true, refill: false, share: true, ready: true });
    assert.equal(i.items[1].breaks, true);
    assert.deepEqual(i.tree, { walk: 0.5, safe: true, start: false });
    assert.equal(i.nextDue, 2.5);
    assert.deepEqual(i.safeSpot, { x: -500, y: -500, walk: 2.5 });
    assert.equal(i.courier.eta, 20);
    assert.deepEqual(i.shop, [{ name: 'tango', cost: 90, hp: 336, mp: 0 }]);
    assert.deepEqual(i.allies, [{ pid: 1, missing: 300, heals: 2 }]);
    assert.deepEqual(i.safe, { kill: 300, hitting: true, reach: 1 });
});

test('a step 2 line reads its old danger inputs as the nearest it can: the kill line from laneBurst, a tree in 600 nearer us', () => {
    const i = inputsOf(parseLog(line(100, `cut ${OLD} ak=none why=fine`))[0].events[0]);
    assert.equal(i.items[0].ready, undefined);
    assert.deepEqual(i.tree, { walk: 0, safe: true });
    assert.ok(Math.abs(i.safe.kill * 1.5 - 250) < 1e-9);
    assert.equal(i.safe.reach, 1);
});

test('a shadow tango 6 s before the game uses one is matched with its lead; a salve the game never drinks is shadow only; a trip home the shadow did not want is avoided', () => {
    const lines = [
        line(1, 'bot pid=0 team=2 ours=Sustain:1'),
        line(1, 'bot pid=5 team=3 ours=Sustain:0'),
        line(100, `cut ${CUT} ak=use anm=tango why=top_up`),
        line(100.5, `cut ${CUT} ak=use anm=tango why=top_up`),
        line(106, 'regen_obs pid=0 item=tango state=start by=oha'),
        line(110, `cut ${CUT} ak=step_out_use anm=flask why=top_up`),
        line(130, 'regen_obs pid=0 item=clarity state=start by=ours'),
        line(140, `cut ${CUT} ak=none why=fine`),
        line(150, 'snap pid=0 x=0 y=0 alive=1 deaths=0'),
        line(170, 'snap pid=0 x=-6500 y=-6300 alive=1 deaths=0'),
    ];
    const d = diffGame(parseLog(lines.join('\n'))[0], 'x.log');
    const g = (k) => d.groups.get(k);
    assert.equal(g('ours use tango matched').n, 1);
    assert.deepEqual(g('ours use tango matched').leads, [6]);
    assert.equal(g('ours use salve shadow_only').n, 1);
    assert.equal(g('ours home - trip_avoided').n, 1);
    assert.equal(g('ours use clarity game_only_ours').n, 1);
    assert.equal(d.heroes, 1);
});

test('a shadow home followed by an arrival within a minute is matched; a respawn is no arrival', () => {
    const lines = [
        line(1, 'bot pid=0 team=2 ours=Sustain:1'),
        line(100, `cut ${CUT} ak=home why=cannot_stay`),
        line(100, 'snap pid=0 x=0 y=0 alive=1 deaths=0'),
        line(140, 'snap pid=0 x=-6500 y=-6300 alive=1 deaths=0'),
        line(200, `cut ${CUT} ak=none why=fine`),
        line(200, 'snap pid=0 x=0 y=0 alive=1 deaths=0'),
        line(260, 'snap pid=0 x=-6500 y=-6300 alive=1 deaths=1'),
    ];
    const d = diffGame(parseLog(lines.join('\n'))[0], 'x.log');
    assert.equal(d.groups.get('ours home cannot_stay matched').n, 1);
    assert.equal(d.groups.get('ours home - trip_avoided'), undefined);
});
