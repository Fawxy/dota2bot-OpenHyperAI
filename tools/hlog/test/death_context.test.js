'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'death_context.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-dctx-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

test('death context: idle seconds split by enemy hero reach, the enemy wave front and a tower; actions and hits apart', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=3')];
    // Core pid 1 on the bot lane, 20 s before its death at t=229 (snapshots each second, at 210..229):
    //   210-214 laning, no target, 1,000 from the enemy hero and 800 from the enemy front: idle only
    //   215-219 laning, no target, the enemy (range 500) 550 away and the enemy front 400 away: idle, reach, creep
    //   220-224 attacking the enemy hero (an action) while hit by it: reach and hit, not idle
    //   225-229 retreat at 30% HP, hit: retreat, low, hit, not idle
    for (let t = 210; t <= 229; t++) {
        const near = t >= 215 && t < 225;
        const mode = t < 220 ? 'laning' : t < 225 ? 'attack' : 'retreat';
        const tgt = t >= 220 && t < 225 ? ' tgt=npc_dota_hero_h6' : '';
        const hp = t >= 225 ? 30 : 80;
        const hit = t >= 220 ? 1 : 0;
        lines.push(line(t, `snap pid=1 x=1000 y=-6000 alive=1 hp=${hp} mode=${mode} d=0.3 deaths=0 ln=bot ol=0 ar=500 hit=${hit}${tgt}`));
        lines.push(line(t, `snap pid=6 x=${near ? 1550 : 2000} y=-6000 alive=1 hp=90 mode=laning d=0.3 deaths=0 ln=bot ol=0 ar=500 hit=0`));
        const fx = near ? 1400 : 1800;
        lines.push(line(t, `front team=3 top=0 topx=0 topy=0 mid=0 midx=0 midy=0 bot=0.5 botx=${fx} boty=-6000`));
        lines.push(line(t, `front team=2 top=0 topx=0 topy=0 mid=0 midx=0 midy=0 bot=0.5 botx=900 boty=-6000`));
    }
    lines.push(line(259, 'snap pid=1 x=-7000 y=-7000 alive=1 hp=100 mode=laning d=0.3 deaths=1 ln=bot ol=0 ar=500 hit=0'));
    const out = run(lines);
    assert.deepStrictEqual(out.map(r => [r.pid, r.t, r.cause, r.secs, r.idle, r.idle_reach, r.idle_creep, r.idle_tower, r.reach, r.hit, r.hit_idle, r.retreat, r.low, r.swaps, r.en_last]),
        [[1, 229, 'retreat', 20, 10, 5, 5, 0, 10, 10, 0, 5, 5, 2, 1]]);
});
