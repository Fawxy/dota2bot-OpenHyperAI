'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'core_spot.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cspot-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

test('core spot: idle seconds and HP lost inside the enemy wave ring and outside it, walks to a last hit apart, tower seconds, our spot by deciding limit', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=4 hero=h4 team=2 pos=4')];
    // Core pid 1 on the bot lane, the enemy front at x=1400 throughout:
    //   100-104 idle 400 from the front (inside 520), an enemy hero 600 away, losing 10 a second
    //   105-109 idle 900 from it, losing 2 a second
    //   110-111 swinging at a creep inside the ring (an action, not counted), losing 5
    //   112-113 idle beside the Dire bot T1 (6269, -2240), far from the front
    let hp = 100;
    for (let t = 100; t <= 113; t++) {
        const x = t < 105 ? 1000 : t < 110 ? 500 : t < 112 ? 1000 : 6269;
        const y = t < 112 ? -6000 : -2600;
        const tgt = t >= 110 && t < 112 ? ' tgt=npc_dota_creep_badguys_melee' : '';
        lines.push(line(t, `snap pid=1 x=${x} y=${y} alive=1 hp=${hp} mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=0${tgt}${t < 105 ? ' ed=600' : ''}`));
        lines.push(line(t, `snap pid=4 x=1000 y=-6000 alive=1 hp=100 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=500 hit=0`));
        lines.push(line(t, `front team=3 top=0 topx=0 topy=0 mid=0 midx=0 midy=0 bot=0.5 botx=1400 boty=-6000`));
        hp -= t < 105 ? 10 : t < 110 ? 2 : t < 112 ? 5 : 0;
    }
    lines.push(line(101, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front pushed=3 why=creep hm=0 hph=0'));
    // The body walks to a last hit at 105; the next sample lands at 106, so only 105 is the picker's (2 HP-% lost).
    lines.push(line(105, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front hph=0 label=lasthit'));
    lines.push(line(106, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front pushed=0 why=pref hm=0 hph=0'));
    lines.push(line(107, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front pushed=5 why=hp hm=200 hph=0'));
    // At 108 the core is 400 from its spot: 108 and 109 are off it, 4 HP-% lost.
    lines.push(line(108, 'lane_pos pid=1 d=400 owned=1 running=1 mode=2 spot=front pushed=4 why=hero hm=0 hph=0'));
    const out = run(lines);
    assert.deepStrictEqual(out.map(r => [r.pid, r.lh_walk, r.lh_walk_hpl, r.idle, r.ring, r.ring_hpl, r.out_hpl, r.tower, r.near, r.near_hpl, r.hpl, r.off, r.off_hpl, r.why_pref, r.why_hero, r.why_creep, r.why_hp]),
        [[1, 1, 2, 11, 5, 50, 8, 2, 5, 50, 58, 2, 4, 1, 1, 1, 1]]);
});

test('core spot: at the 1 s cadence a walk to a last hit or an off-spot sample covers only its own second', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1')];
    for (let t = 100; t <= 104; t++) {
        lines.push(line(t, `snap pid=1 x=0 y=-6000 alive=1 hp=${100 - 3 * (t - 100)} mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=0`));
        lines.push(line(t, `front team=3 top=0 topx=0 topy=0 mid=0 midx=0 midy=0 bot=0.5 botx=3000 boty=-6000`));
        lines.push(line(t, `lane_pos pid=1 d=${t === 102 ? 400 : 10} owned=1 running=1 mode=2 spot=front pushed=0 why=pref hm=0 hph=0${t === 100 ? ' label=lasthit' : ''}`));
    }
    const [r] = run(lines);
    // 100 the walk (3 lost); 101-104 the spot's (9 lost, 104 has no next snapshot); only 102 off.
    assert.deepStrictEqual([r.lh_walk, r.lh_walk_hpl, r.idle, r.hpl, r.off, r.off_hpl], [1, 3, 4, 9, 1, 3]);
});

test('core spot: pos_lo and pos_hi read the supports the same way, and the default leaves them out', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=4 hero=h4 team=2 pos=4')];
    for (let t = 100; t <= 103; t++) {
        lines.push(line(t, `snap pid=1 x=0 y=-6000 alive=1 hp=100 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=0`));
        lines.push(line(t, `snap pid=4 x=0 y=-6000 alive=1 hp=${100 - 4 * (t - 100)} mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=500 hit=0 ed=700`));
        lines.push(line(t, `front team=3 top=0 topx=0 topy=0 mid=0 midx=0 midy=0 bot=0.5 botx=3000 boty=-6000`));
    }
    lines.push(line(100, 'lane_pos pid=4 d=10 owned=1 running=1 mode=2 spot=oha hph=0'));
    assert.deepStrictEqual(run(lines).map(r => r.pid), [1]);
    const sup = run(lines, { pos_lo: 4, pos_hi: 5 });
    assert.deepStrictEqual(sup.map(r => [r.pid, r.idle, r.hpl, r.near]), [[4, 4, 12, 4]]);
});
