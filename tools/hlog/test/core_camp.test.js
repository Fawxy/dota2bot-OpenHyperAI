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

test('gates: per-minute tallies summed by position, a camp fitting counted from skips and starts', () => {
    const out = run('core_camp_gates.sql', [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=2 hero=h2 team=2 pos=2'),
        line(180, 'core_camp pid=1 pos=1 lane=3 phase=gates min=2 h_wave=40 h_gap=15 h_skip=3 h_trip=1'),
        line(240, 'core_camp pid=1 pos=1 lane=3 phase=gates min=3 h_wave=60'),
        line(240.5, 'core_camp pid=2 pos=2 lane=2 phase=gates min=3 h_mode=50 h_plan=10'),
        line(250, 'core_camp pid=1 pos=1 lane=3 phase=skip clash=270 win=9 why=threat camp=1'),
    ]);
    assert.deepStrictEqual(out.map((r) => [r.pos, r.cores, r.secs, r.wave, r.gap, r.mode, r.no_plan, r.fit]), [
        [1, 1, 119, 100, 15, 0, 0, 4],
        [2, 1, 60, 0, 0, 50, 10, 0],
    ]);
});


const snap = (t, pid, hp) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=${hp} mp=100 lvl=5 lh=0 dn=0 kills=0 deaths=0 ln=bot s=0 ld=0 mode=laning d=0 act=1 gold=0 ol=0 od=0 ar=550 hit=0`);
const kill = (t, pid) => line(t, `neutral_death pid=${pid} team=2 by=${pid}`);
const endHpe = (t, pid, hpe, hpr, clrm) => line(t, `core_camp pid=${pid} pos=1 lane=3 phase=end clash=0 win=0 res=ok why=back camp=1 camps=1 ret=0 g0=0 g1=0 secs=30 hpe=${hpe} hpr=${hpr} clre=10 clrm=${clrm} hpm=0.05`);

test('price truth: the HP lost to damage between snapshots, not the net change; signed against the live and the table price', () => {
    const out = run('core_camp_price.sql', [
        line(100, 'core_camp pid=1 pos=1 lane=3 phase=start clash=130 win=4 camp=1 type=small src=table ret=120 clr=9 hpt=0.30 gold=80 loss=0 net=80'),
        // 100 -> 80 -> 85 (regen) -> 70: 35 points of damage, 15 net.
        snap(104, 1, 100), snap(106, 1, 80), snap(108, 1, 85), snap(110, 1, 70), snap(112, 1, 72),
        kill(109, 1), kill(110.5, 1),
        endHpe(120, 1, 0.80, 0.5, 6),
    ], { like: '%' });
    assert.strictEqual(out.length, 1);
    assert.strictEqual(out[0].dmg, 0.35);
    assert.strictEqual(out[0].pred, 0.4);
    assert.strictEqual(out[0].err, 0.05);
    assert.strictEqual(out[0].terr, -0.05);
});

test('refusal precision: a would-refuse camp cleared anyway, with the damage it cost and whether it breached ArriveHP', () => {
    const admit = (t, pid, v, hp) => line(t, `core_camp pid=${pid} pos=1 lane=3 phase=admit camp=2 type=large src=table lvl=4 hpc=0.55 clr=20 hpe=1.2 clre=30 hp=${hp} hpr=0.55 pace=0.7 v=${v}`);
    const out = run('core_camp_admit.sql', [
        admit(200, 1, 'hp', 1), snap(201, 1, 100), snap(210, 1, 40), snap(220, 1, 20), kill(222, 1), endHpe(240, 1, 1.2, 0.55, 22),
        admit(300, 2, 'ok', 1), snap(301, 2, 100), snap(310, 2, 90), kill(312, 2), endHpe(330, 2, 0.2, 0.55, 12),
    ], { like: '%' });
    const a = out.find((r) => r.pid === 1);
    const b = out.find((r) => r.pid === 2);
    assert.deepStrictEqual([a.v, a.dmg, a.breach], ['hp', 0.8, 1]);
    assert.deepStrictEqual([b.v, b.dmg, b.breach], ['ok', 0.1, 0]);
});
