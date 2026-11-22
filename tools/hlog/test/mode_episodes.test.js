'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'mode_episodes.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-me-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

const snap = (t, pid, hp, extra) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=${hp} mode=attack d=0.8 kills=0 deaths=0${extra}`);

test('mode_episodes: an episode takes its entry state and its exit from the hero\'s own mode rows', () => {
    const out = run([
        line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5'),
        line(10.5, 'mode pid=2 from=laning to=attack d=0.6 dwell=5'),
        snap(10.2, 1, 90, ' ed=400 ah=0 ce=2 tgt=npc_dota_hero_lion tid=h6'),
        snap(11.2, 1, 80, ' ed=300 ah=1 ce=2 tgt=npc_dota_hero_lion tid=h6 kills=1'),
        snap(12.2, 1, 60, ' ed=300 ah=1 ce=2 tid=u9'),
        line(13, 'mode pid=2 from=attack to=retreat d=0.9 dwell=2.5'),
        line(14, 'mode pid=1 from=attack to=laning d=0.4 dwell=4'),
        line(30, 'mode pid=1 from=laning to=attack d=0.55 dwell=16'),
    ]);
    const a = out.find(r => r.pid === 1 && r.t === 10);
    assert.deepStrictEqual(
        { secs: a.secs, prev: a.prev, nxt: a.nxt, hp0: a.hp0, hp1: a.hp1, ed0: a.ed0, ah0: a.ah0, ce0: a.ce0, sn: a.sn, tgt_hero: a.tgt_hero },
        { secs: 4, prev: 'laning', nxt: 'laning', hp0: 90, hp1: 60, ed0: 400, ah0: 0, ce0: 2, sn: 3, tgt_hero: 2 });
    const b = out.find(r => r.pid === 2);
    assert.strictEqual(b.nxt, 'retreat');
    assert.strictEqual(b.secs, 2.5);
    assert.strictEqual(b.hp0, null);
    const open = out.find(r => r.pid === 1 && r.t === 30);
    assert.strictEqual(open.nxt, null);
});

test('mode_episodes: the mode param picks another mode and the window limits entries', () => {
    const lines = [
        snap(5, 9, 100, ' ed=1 ah=0 ce=0 tid=h2'),
        line(10, 'mode pid=1 from=laning to=retreat d=0.8 dwell=5'),
        line(20, 'mode pid=1 from=retreat to=laning d=0.4 dwell=10'),
        line(800, 'mode pid=1 from=laning to=retreat d=0.8 dwell=780'),
    ];
    assert.strictEqual(run(lines, { mode: 'retreat' }).length, 1);
    assert.strictEqual(run(lines, { mode: 'retreat', until: 900 }).length, 2);
    assert.strictEqual(run(lines).length, 0);
});
