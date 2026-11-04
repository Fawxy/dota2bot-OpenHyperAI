'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const read = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', name), 'utf8');

function run(name, lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cc-')), 'a.log');
    // The parser starts a new game when time goes back: cases are written in any order and sorted here.
    const at = (l) => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(read(name), params);
    s.db.close();
    return out;
}

const start = (t, pid, ret, loss) => line(t, `core_camp pid=${pid} pos=1 lane=3 phase=start clash=${t + 30} win=${Math.floor((t + 30) / 30)} camp=1 type=small ret=${ret} clr=9 gold=80 loss=${loss} net=${80 - loss}`);
const end = (t, pid, why, back, g0, g1, secs) =>
    line(t, `core_camp pid=${pid} pos=1 lane=3 phase=end clash=0 win=0 res=ok why=${why} camp=1 camps=1 ret=0${back === null ? '' : ` back=${back}`} g0=${g0} g1=${g1} secs=${secs}`);

test('per trip: back by the planned return + 5, gold above passive against the forecast loss, own neutral kills, a death', () => {
    const out = run('core_camp.sql', [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        // Trip 1: back at ret + 4, +80 gold in 20 s (50 above passive) against a loss of 40; two of its neutrals, one an ally's.
        start(300, 1, 320, 40),
        line(305, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=1 camp=1 np=1 nd=100'),
        line(306, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=1 camp=1 np=1 nd=100'),
        line(307, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=5 camp=1 np=5 nd=100'),
        end(324, 1, 'back', 324, 500, 580, 20),
        // Trip 2: back at ret + 6 (late), +40 gold in 20 s (10 above passive) against a loss of 20, and the core dies 2 s after it.
        start(400, 1, 420, 20),
        end(426, 1, 'back', 426, 600, 640, 20),
        line(427, 'snap pid=1 hp=50'),
        line(428, 'snap pid=1 hp=0'),
        // Trip 3: ended by a threat on the way, no walk back; a neutral death after its end is not the trip's.
        start(500, 1, 530, 0),
        end(505, 1, 'interrupted:threat', null, 700, 705, 5),
        line(510, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=1 camp=1 np=1 nd=100'),
    ]);
    assert.deepStrictEqual(out.map((r) => [r.t, r.why, r.back_ok, r.gain, r.paid, r.nk, r.died]), [
        [300, 'back', 1, 50, 1, 2, 0],
        [400, 'back', 0, 10, 0, 0, 1],
        [500, 'interrupted:threat', 0, -2.5, 0, 0, 0],
    ]);
});

test('coverage: a window with a fitted camp and a skip but no start counts missed under its first skip reason', () => {
    const out = run('core_camp_cover.sql', [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(300, 'core_camp pid=1 pos=1 lane=3 phase=skip clash=330 win=11 why=threat camp=1'),
        line(301, 'core_camp pid=1 pos=1 lane=3 phase=skip clash=330 win=11 why=mate-job camp=1'),
        line(302, 'core_camp pid=1 pos=1 lane=3 phase=start clash=330 win=11 camp=1'),
        line(360, 'core_camp pid=1 pos=1 lane=3 phase=skip clash=390 win=13 why=threat camp=1'),
        line(390, 'core_camp pid=1 pos=1 lane=3 phase=skip clash=420 win=14 why=enemy-missing camp=1'),
    ]);
    assert.deepStrictEqual(out.map((r) => [r.why, r.windows, r.trips, r.missed]), [
        ['threat', 2, 1, 1],
        ['enemy-missing', 1, 0, 1],
    ]);
});
