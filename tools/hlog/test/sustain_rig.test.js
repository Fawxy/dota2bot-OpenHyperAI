'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { parseLog } = require('../parse');
const { readGame, summary } = require('../sustain_rig');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const ready = (t, pid, task, ok = 1, fail) =>
    line(t, `drill ph=ready name=sustain pid=${pid} rep=1 var=rot1 task=${task} ok=${ok}${fail ? ` fail=${fail}` : ''} secs=60 hp=0.25 mp=1 rend=168 win=600`);
const snap = (t, pid, x, y, hp, deaths = 0) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${hp} deaths=${deaths} mode=laning`);

function game(lines) {
    return readGame(parseLog(lines.join('\n'))[0], 'x.log');
}

test('each task is graded on its own act inside the window from release to the rep end', () => {
    const g = game([
        line(60, 'drill ph=role name=sustain pid=0 team=2 role=cast'),
        ready(120, 0, 'tango'),
        ready(120, 1, 'salve'),
        ready(120, 2, 'home'),
        ready(120, 3, 'ship'),
        ready(120, 4, 'tango_ship'),
        ready(120, 5, 'bottle', 0, 'tree'),
        line(122, 'sustain pid=0 k=use it=item_tango why=top_up hp0=150 hp1=160 sec=0.5 ed=started'),
        line(130, 'sustain pid=1 k=step_out_use it=item_flask why=top_up hp0=150 hp1=400 sec=6 ed=interrupted'),
        snap(121, 2, -3000, -5000, 25),
        snap(140, 2, -6600, -6300, 50),
        snap(146, 2, -6600, -6300, 82),
        line(140, 'sustain pid=3 k=buy it=item_flask why=cannot_stay sec=15 ed=delivered'),
        line(150, 'sustain pid=3 k=use it=item_flask why=top_up sec=1 ed=started'),
        line(123, 'sustain pid=4 k=use it=item_tango why=tango_ship sec=1 ed=started'),
        line(200, 'sustain pid=4 k=buy it=item_flask why=tango_ship sec=40 ed=delivered'),
    ]);
    const by = Object.fromEntries(g.rows.map((r) => [r.task, r]));
    assert.equal(g.ready.n, 5);
    assert.equal(g.ready.m, 6);
    assert.deepEqual(g.ready.fails, { tree: 1 });
    assert.equal(by.tango.done, 1);
    assert.equal(by.tango.secs, 1.5);
    assert.equal(by.salve.done, 1, 'a step-out ended interrupted still used the salve');
    assert.equal(by.home.done, 1);
    assert.equal(by.home.secs, 26);
    assert.equal(by.ship.done, 1);
    assert.equal(by.tango_ship.done, 0, 'the delivery after the rep end is not counted');
    const s = summary(g.rows);
    assert.equal(s.tango_ship.done, 0);
    assert.equal(s.home.share, 100);
});

test('a missed use, a walk home that never heals, a buy never used: not done; OHA side read from regen_obs', () => {
    const g = game([
        line(1, 'bot pid=0 ours=Retreat:1,Sustain:0'),
        ready(120, 0, 'tango'),
        ready(120, 1, 'home'),
        ready(120, 2, 'ship'),
        ready(120, 3, 'salve'),
        ready(120, 4, 'bottle'),
        line(130, 'sustain pid=0 k=use it=item_tango why=top_up sec=8 ed=missed'),
        snap(140, 1, -6600, -6300, 60),
        line(140, 'sustain pid=2 k=buy it=item_flask why=cannot_stay sec=15 ed=delivered'),
        line(125, 'regen_obs by=oha pid=3 item=salve state=start'),
    ]);
    const by = Object.fromEntries(g.rows.map((r) => [r.task, r]));
    assert.equal(by.tango.done, 0);
    assert.equal(by.home.done, 0);
    assert.equal(by.ship.done, 0);
    assert.equal(by.salve.done, 1);
    assert.equal(by.salve.by, 'oha');
    assert.equal(by.bottle.done, null, 'a bottle with nothing of ours is not graded: OHA bottle use is not observed');
    assert.equal(summary(g.rows).bottle.graded, 0);
});

test('switch on: a bottle rep with nothing of ours is a miss, not ungraded', () => {
    const g = game([line(1, 'bot pid=0 ours=Retreat:1,Sustain:1'), ready(120, 4, 'bottle')]);
    assert.equal(g.rows[0].done, 0);
});
