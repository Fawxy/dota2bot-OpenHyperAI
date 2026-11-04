'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const q = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

function run(lines, name, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rune-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(q(name), params);
    s.db.close();
    return out;
}

const bots = [line(0, 'bot pid=2 hero=h2 team=2 pos=2'), line(0, 'bot pid=3 hero=h3 team=2 pos=4'), line(0, 'bot pid=4 hero=h4 team=2 pos=5')];

test('rune spawn: a plan is covered only when every planned hero reached its spot by the spawn; acts counted', () => {
    const lines = [...bots, line(320, 'rune_plan team=2 mid=2 ms=0 sup=3 ss=1'),
        line(362, 'rune_job pid=2 pos=2 kind=power spawn=360 res=ok why=ok arr=359.8 died=0 phase=take hid=5.2'),
        line(361, 'rune_job pid=3 pos=4 kind=power spawn=360 res=fail why=no_target:rune\\ missing arr=360.4 died=0 phase=none hid=6'),
        // The other support skipped by the plan is not a planned trip.
        line(330, 'rune_job pid=4 pos=5 kind=power spawn=360 res=skip why=plan-other')];
    const r = run(lines, 'rune_spawn')[0];
    assert.deepStrictEqual([r.trips, r.covered, r.take, r.take_ok, r.none, r.hid], [2, 1, 1, 1, 1, 5.6]);
    lines[5] = line(366, 'rune_job pid=3 pos=4 kind=power spawn=360 res=fail why=timeout:late died=0');
    const late = run(lines, 'rune_spawn')[0];
    assert.deepStrictEqual([late.covered, late.late], [0, 1]);
});

test('rune spawn: a dropped support\'s spot handed on: the last plan line names the planned heroes', () => {
    const lines = [...bots, line(320, 'rune_plan team=2 mid=2 ms=0 sup=3 ss=1'),
        line(347, 'rune_job pid=3 pos=4 kind=power spawn=360 res=skip why=low-hp'),
        line(347, 'rune_plan team=2 mid=2 ms=0 sup=4 ss=1 why=swap:low-hp'),
        line(362, 'rune_job pid=2 pos=2 kind=power spawn=360 res=ok why=ok arr=359.8 died=0 phase=take hid=5'),
        line(361, 'rune_job pid=4 pos=5 kind=power spawn=360 res=fail why=cancelled:off arr=359.9 died=0 phase=off')];
    const out = run(lines, 'rune_spawn');
    assert.deepStrictEqual(out.map(r => [r.sup, r.swaps, r.trips, r.covered]), [[4, 1, 2, 1]]);
});

test('rune plays: chances, fires and ends by kind, an unended fired play counted', () => {
    const lines = [...bots,
        line(370, 'play pid=3 kind=gank tgt=7 w=0.3 fire=1 id=1 draw=0.1'),
        line(380, 'play_end id=1 pid=3 kind=gank tgt=7 res=kill why=kill join=1 dur=9'),
        line(371, 'play pid=4 kind=gank tgt=7 w=0 zero=tower fire=0'),
        line(372, 'play pid=2 kind=rune_fight tgt=8 w=0.5 fire=1 id=2 draw=0.2')];
    const out = run(lines, 'rune_plays').map(r => [r.kind, r.chances, r.fired, r.zero_tower, r.ended, r.kill, r.joins, r.unended]);
    assert.deepStrictEqual(out, [['gank', 2, 1, 1, 1, 1, 1, 0], ['rune_fight', 1, 1, 0, 0, 0, 0, 1]]);
});

test('rune try: a give-up whose hero stays at the spot 5 s later is held', () => {
    const snap = (t, x) => line(t, `snap pid=2 x=${x} y=1112 alive=1 hp=100 mode=rune d=0.3 deaths=0 ln=mid s=0.3 ld=0 ol=0 ar=550 hit=0`);
    const lines = [...bots, line(1, 'rune_try pid=2 rune=0 res=try d=20 act0=12 act=12 st=1 dt=0'),
        line(4, 'rune_try pid=2 rune=0 res=gave_up d=20 act0=12 act=12 st=1 dt=3'), snap(3.5, -1640), snap(10, -1630)];
    const held = run(lines, 'rune_try').map(r => [r.rune, r.res, r.n, r.act, r.held_after]);
    assert.deepStrictEqual(held, [[0, 'gave_up', 1, 12, 1], [0, 'try', 1, 12, null]]);
    lines[lines.length - 1] = snap(10, -900);
    assert.strictEqual(run(lines, 'rune_try')[0].held_after, 0);
});
