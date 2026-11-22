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

test('mode_episodes: an episode with no snapshot of its own has no entry state, even when a later one exists', () => {
    const out = run([
        snap(9, 1, 100, ' ed=900 ah=0 ce=0'),
        line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5'),
        line(10.4, 'mode pid=1 from=attack to=laning d=0.45 dwell=0.4'),
        snap(10.6, 1, 70, ' ed=300 ah=1 ce=3 hit=1'),
    ]);
    const a = out[0];
    assert.deepStrictEqual({ hp0: a.hp0, ed0: a.ed0, ah0: a.ah0, ce0: a.ce0, hit0: a.hit0, sn: a.sn }, { hp0: null, ed0: null, ah0: null, ce0: null, hit0: null, sn: 0 });
});

test('mode_episodes: hit0 is the API\'s damaged-by-a-hero flag at entry, apart from ah0 (heroes targeting the hero)', () => {
    const out = run([
        line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5'),
        snap(10.2, 1, 90, ' ed=400 ah=0 ce=0 hit=1'),
        line(12, 'mode pid=1 from=attack to=laning d=0.4 dwell=2'),
    ]);
    assert.deepStrictEqual({ hit0: out[0].hit0, ah0: out[0].ah0 }, { hit0: 1, ah0: 0 });
});

test('mode_episodes: a kill is counted in one episode of the mode, never negative, and from the entry itself', () => {
    const out = run([
        snap(9.5, 1, 100, ' kills=0'),
        line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5'),
        snap(10.5, 1, 100, ' kills=1'),
        line(11, 'mode pid=1 from=attack to=laning d=0.4 dwell=1'),
        line(12, 'mode pid=1 from=laning to=attack d=0.77 dwell=1'),
        snap(12.5, 1, 100, ' kills=2'),
        line(13, 'mode pid=1 from=attack to=laning d=0.4 dwell=1'),
        line(20, 'mode pid=1 from=laning to=attack d=0.77 dwell=7'),
        line(20.5, 'mode pid=1 from=attack to=laning d=0.4 dwell=0.5'),
        snap(30, 1, 100, ' kills=3'),
    ]);
    assert.deepStrictEqual(out.map(r => r.kills), [1, 1, 0]);
});

test('mode_episodes: an episode that spans a death says so, and how many of its seconds the hero was dead', () => {
    const out = run([
        line(18, 'mode pid=1 from=laning to=retreat d=0.9 dwell=5'),
        snap(19, 1, 20, ' deaths=0'),
        snap(20, 1, 5, ' deaths=0'),
        line(45, 'mode pid=1 from=retreat to=laning d=0.45 dwell=27'),
        snap(45, 1, 100, ' deaths=1'),
        line(50, 'mode pid=1 from=laning to=retreat d=0.9 dwell=5'),
        snap(50.5, 1, 100, ' deaths=1'),
        line(52, 'mode pid=1 from=retreat to=laning d=0.45 dwell=2'),
        snap(53, 1, 100, ' deaths=1'),
    ], { mode: 'retreat' });
    assert.deepStrictEqual(out.map(r => [r.died, r.dead_secs, r.hp1]), [[1, 24, 5], [0, 0, 100]]);
});

test('mode_episodes: an episode the game ended in reads its snapshots to the end of the log', () => {
    const lines = [line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5')];
    for (let t = 10.5; t < 60; t += 1) lines.push(snap(t, 1, 90, ' tid=h6'));
    const a = run(lines)[0];
    assert.deepStrictEqual({ secs: a.secs, sn: a.sn, tgt_hero: a.tgt_hero }, { secs: null, sn: 50, tgt_hero: 50 });
});

test('mode_episodes: mode and snapshot rows are read for the games picked, not scanned across the store', () => {
    const s = new Store(':memory:');
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-me-')), 'a.log');
    fs.writeFileSync(f, [line(10, 'mode pid=1 from=laning to=attack d=0.77 dwell=5'), snap(10.2, 1, 90, '')].join('\n') + '\n');
    s.ingest(f);
    s.refreshViews();
    const plan = s.query(`EXPLAIN QUERY PLAN ${sql}`, {}).map(r => r.detail);
    s.db.close();
    assert.ok(!plan.some(d => /^SCAN (m|ev_mode|s|ev_snap)\b/.test(d)), plan.join('\n'));
});
