'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'idle_threat.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ithreat-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

test('idle threat: idle HP by the nearest enemy hero (any state), its kind and distance, on or off the spot, walks to a last hit apart', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=4'), line(0, 'bot pid=7 hero=h7 team=3 pos=5')];
    // Melee core pid 1 at x=0. Enemy melee pid 6 and ranged pid 7 (by their own snapshots, so fogged ones count too):
    //   100-102 melee 500 away, ranged 1200: nearest melee, 0-600; hits flagged on the 101 and 102 snapshots
    //   103-104 melee 900, ranged 700: nearest ranged, 600-800
    //   105-106 a walk to a last hit (label at 105, carried into 106): not counted
    //   107-108 melee 1100, ranged dead: nearest melee, 1000+
    // HP falls 5 a second to 103, then 2, then 3 in the walk, then 1.
    const hpAt = { 100: 100, 101: 95, 102: 90, 103: 85, 104: 83, 105: 81, 106: 78, 107: 75, 108: 74 };
    for (let t = 100; t <= 108; t++) {
        const mx = t <= 102 ? 500 : t <= 104 ? 900 : 1100;
        const rx = t <= 102 ? 1200 : t <= 104 ? 700 : 1200;
        const hit = t === 101 || t === 102 ? 1 : 0;
        lines.push(line(t, `snap pid=1 x=0 y=0 alive=1 hp=${hpAt[t]} mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=${hit}`));
        lines.push(line(t, `snap pid=6 x=${mx} y=0 alive=1 hp=100 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=150 hit=0`));
        lines.push(line(t, `snap pid=7 x=${rx} y=0 alive=${t >= 107 ? 0 : 1} hp=100 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=550 hit=0`));
    }
    // Spot distance: on at 100 (100, 101), off at 102 (102, 103), no sample for 104, on again from 107.
    lines.push(line(100, 'lane_pos pid=1 d=50 owned=1 running=1 mode=2 spot=front hph=0 label=hold'));
    lines.push(line(102, 'lane_pos pid=1 d=400 owned=1 running=1 mode=2 spot=front hph=0 label=hold'));
    lines.push(line(105, 'lane_pos pid=1 d=10 owned=1 running=1 mode=2 spot=front hph=0 label=lasthit'));
    lines.push(line(107, 'lane_pos pid=1 d=20 owned=1 running=1 mode=2 spot=front hph=0 label=hold'));
    const out = run(lines).map(r => [r.ek, r.me, r.band, r.spot, r.secs, r.hpl, r.hit]);
    out.sort((a, b) => a.join().localeCompare(b.join()));
    assert.deepStrictEqual(out, [
        ['melee', 'melee', '0-600', 'off', 1, 5, 0],
        ['melee', 'melee', '0-600', 'on', 2, 10, 2],
        ['melee', 'melee', '1000+', 'on', 2, 1, 0],
        ['ranged', 'melee', '600-800', '?', 1, 2, 0],
        ['ranged', 'melee', '600-800', 'off', 1, 2, 0],
    ]);
});
