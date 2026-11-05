'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

function run(lines, sql) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pw-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql);
    s.db.close();
    return out;
}

// Team 2: pid 1 its pos 1 core, pid 3 pos 4, pid 5 pos 5 (the puller); pid 6 the other team's core. Our bot front at the slot
// is (0, -6000); camp 13's spawn is (-2415, -8402).
const bots = [
    line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    line(0, 'bot pid=3 hero=h3 team=2 pos=4'),
    line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
    line(0, 'bot pid=6 hero=h6 team=3 pos=1'),
];
const cd = (t, x, y, by, tw, kind = 'melee') => line(t, `creep_death team=2 kind=${kind} x=${x} y=${y} hp=0.05 by=${by} tw=${tw}`);

test('an ok pull: their wave near our front in slot..slot+75 by fate, our own creeps there, the lane at 30 s and the next meet against the target', () => {
    const out = run([...bots,
        line(195, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=200 res=ok why=ok dt=1'),
        line(240, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=241 res=fail why=cancelled:empty'),
        line(200, 'lane_read team=2 lane=3 eq=0.2 fx=0 fy=-6000 tw=1'),
        line(230, 'lane_read team=2 lane=3 eq=-0.9 fx=0 fy=-6000 tw=1'),
        // the T1 is down in the first reading after slot + 60, so the meet is read from the next one with tw=1.
        line(261, 'lane_read team=2 lane=3 eq=-0.95 fx=0 fy=-6000 tw=2'),
        line(265, 'lane_read team=2 lane=3 eq=-0.6 fx=0 fy=-6000 tw=1'),
        cd(210, 0, -6000, 1, 0),
        cd(211, 0, -6000, 3, 0),
        cd(212, 0, -6000, 'none', 1),
        cd(213, 0, -6000, 'none', 0),
        // denied by their core: the other team's own_creep_death with a denier, same kind, within 1 s and 250.
        cd(214, 100, -6000, 'none', 0),
        line(214.2, 'own_creep_death team=3 kind=melee x=120 y=-6000 hp=0.05 by=6'),
        cd(215, 0, -6000, 1, 1),
        // outside: at slot + 75, 2,600 from the front, and the other team's log.
        cd(275, 0, -6000, 1, 0),
        cd(216, 0, -3400, 1, 0),
        line(217, 'creep_death team=3 kind=melee x=0 y=-6000 hp=0.05 by=6 tw=0'),
        line(220, 'own_creep_death team=2 kind=melee x=0 y=-6000 hp=0.05 by=1'),
        line(221, 'own_creep_death team=2 kind=melee x=0 y=-6000 hp=0.05 by=none'),
        // the pulled wave at the camp (2,898 from the front): the pulled-wave part, not our side's.
        line(205, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=none'),
    ], 'SELECT * FROM pull_waves');
    assert.deepStrictEqual(out.map(r => [r.slot, r.grp, r.own_died, r.e_dead, r.e_core, r.e_ours, r.e_denied, r.e_tower, r.e_none, r.e_tw,
        r.o_dead, r.o_denied, r.tw30, r.meet_own, r.meet_d, r.meet_tw]),
        // meet: (-0.6 + 1) / 2 * 4,517 (bot T1-T1) = 903 from our T1, 3 past the side-lane target 900.
        [[200, 'ok_div', 1, 6, 2, 1, 1, 1, 1, 2, 2, 1, 1, 903, 3, 0]]);
});

test('control rows: one per team, lane and slot that wanted a pull and got none, not near any pull on that lane; a slot with no front reads null fates', () => {
    const out = run([...bots,
        line(195, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=200 res=ok why=ok dt=0.5'),
        // within 20 s of a pull on that lane: not a control.
        line(214, 'choice pid=5 kind=pull go=0 want=1 lane=3 slot=215'),
        // two supports' lines on one slot are one control.
        line(318, 'choice pid=5 kind=pull go=0 want=1 lane=3 slot=320'),
        line(318, 'choice pid=3 kind=pull go=0 want=1 lane=3 slot=320'),
        line(320, 'lane_read team=2 lane=3 eq=0.1 fx=0 fy=-6000 tw=1'),
        line(350, 'lane_read team=2 lane=3 eq=-0.2 fx=0 fy=-6000 tw=1'),
        // a meet under our T1: (-0.8 + 1) / 2 * 4,517 = 452 <= 700.
        line(381, 'lane_read team=2 lane=3 eq=-0.8 fx=0 fy=-6000 tw=1'),
        cd(330, 0, -6000, 1, 0),
        line(378, 'choice pid=5 kind=pull go=0 want=0 lane=3 slot=380'),
        line(408, 'choice pid=5 kind=pull go=0 want=1 lane=1 slot=410'),
    ], 'SELECT * FROM pull_waves ORDER BY slot');
    assert.deepStrictEqual(out.map(r => [r.slot, r.grp, r.own_died, r.e_dead, r.e_core, r.tw30, r.meet_own, r.meet_tw]),
        [[200, 'ok_undiv', 0, null, null, null, null, null], [320, 'none', null, 1, 1, 0, 452, 1], [410, 'none', null, null, null, null, null, null]]);
});

test('a pull row leaves the pulled wave (within 800 of the camp spawn) out of our creeps at our side; own_died has it', () => {
    const out = run([...bots,
        line(195, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=200 res=ok why=ok dt=1'),
        line(200, 'lane_read team=2 lane=3 eq=0.2 fx=-2000 fy=-7000 tw=1'),
        line(205, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=none'),
        line(206, 'own_creep_death team=2 kind=melee x=-1000 y=-7000 hp=0.05 by=none'),
    ], 'SELECT * FROM pull_waves');
    assert.deepStrictEqual(out.map(r => [r.own_died, r.o_dead]), [[1, 1]]);
});
