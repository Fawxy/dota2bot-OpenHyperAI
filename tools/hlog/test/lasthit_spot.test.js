'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lasthit_spot.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lhspot-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

test('lasthit spot: each core creep death banded by its distance from the spot less attack range, classed as @lasthit_cores does', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=2 hero=h2 team=2 pos=2'), line(0, 'bot pid=6 hero=h6 team=3 pos=1')];
    for (let t = 100; t <= 140; t += 10) {
        lines.push(line(t, `snap pid=1 x=0 y=0 alive=1 hp=100 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=0`));
        lines.push(line(t, `snap pid=2 x=0 y=0 alive=1 hp=100 mode=laning d=0.3 deaths=0 ln=mid ol=0 ar=550 hit=0`));
    }
    // Melee core pid 1, spot at (0, 0); ranged core pid 2, spot at (0, 0) too.
    lines.push(line(99.5, 'lane_pos pid=1 d=50 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=pref hm=0 sx=0 sy=0'));
    lines.push(line(109.0, 'lane_pos pid=1 d=400 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=hero hm=0 sx=0 sy=0'));
    lines.push(line(119.0, 'lane_pos pid=1 d=400 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=hero hm=0 sx=0 sy=0'));
    // 125: a sample 3 s before the death only, too old, and a nearer one on OHA's spot (with sx/sy): the death is dropped.
    lines.push(line(122.0, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=creep hm=0 sx=0 sy=0'));
    lines.push(line(124.5, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=oha hph=0 label=hold why=pref hm=0 sx=0 sy=0'));
    lines.push(line(129.0, 'lane_pos pid=2 d=0 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=creep hm=0 sx=0 sy=0'));
    // Deaths (team 2's to take). Melee: 100 got at 100 from the spot (in range); 110 away at 700 (+600 band: 700-150=550);
    // 120 in_range by the core but 1000 from the spot (beyond); 125 dropped; 130 ranged core swung late, 700 from the spot (+300).
    // 135: pid 6's team, not ours.
    lines.push(line(100, 'creep_death team=2 kind=melee x=100 y=0 hp=0.1 by=1 p1d=100 p1r=150 p1t=1 p1a=0.2'));
    lines.push(line(110, 'creep_death team=2 kind=melee x=700 y=0 hp=0.1 by=none p1d=700 p1r=150 p1t=0'));
    lines.push(line(120, 'creep_death team=2 kind=melee x=1000 y=0 hp=0.1 by=none p1d=300 p1r=150 p1t=0'));
    lines.push(line(125, 'creep_death team=2 kind=melee x=100 y=0 hp=0.1 by=none p1d=100 p1r=150 p1t=0'));
    lines.push(line(130, 'creep_death team=2 kind=ranged x=700 y=0 hp=0.1 by=none p2d=700 p2r=550 p2t=1 p2a=0.3'));
    // 112: an ally's last hit (pid 2) 450 from the spot, exactly attack range + 300: +300 band, away for pid 1 (p1d 600).
    lines.push(line(111.5, 'lane_pos pid=1 d=400 owned=1 running=1 mode=2 spot=front hph=0 label=hold why=hero hm=0 sx=0 sy=0'));
    lines.push(line(112, 'creep_death team=2 kind=melee x=450 y=0 hp=0.1 by=2 p1d=600 p1r=150 p1t=0'));
    lines.push(line(135, 'creep_death team=3 kind=melee x=0 y=0 hp=0.1 by=6 p1d=0 p1r=150 p1t=1 p1a=0.2'));
    const out = run(lines).map(r => [r.me, r.band, r.got, r.swung, r.in_range, r.away, r.hero, r.pref, r.creep]);
    assert.deepStrictEqual(out, [
        ['melee', 'a:in range', 1, 0, 0, 0, 0, 1, 0],
        ['melee', 'b:+300', 0, 0, 0, 1, 1, 0, 0],
        ['melee', 'c:+600', 0, 0, 0, 1, 1, 0, 0],
        ['melee', 'd:beyond', 0, 0, 1, 0, 1, 0, 0],
        ['ranged', 'b:+300', 0, 1, 0, 0, 0, 0, 1],
    ]);
});
