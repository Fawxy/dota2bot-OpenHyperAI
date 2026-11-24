'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ul-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const view = s.query('SELECT * FROM unit_life ORDER BY t1, uid');
    const named = s.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'unit_life.sql'), 'utf8'),
        { game_id: s.query('SELECT game_id FROM games')[0].game_id });
    const byLog = n => s.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'unit_life.sql'), 'utf8'), n === undefined ? { like: '%a.log' } : { like: '%a.log', game: n });
    const lastGame = byLog(), game1 = byLog(1), game2 = byLog(2);
    s.db.close();
    return { view, named, lastGame, game1, game2 };
}

// Team 2 owns the creeps; team 3's heroes (pids 5, 6) write creep_death for them, team 2's pid 1 denies.
const wave = (t, cid, by, x = 0, y = 0, kind = 'melee') =>
    line(t, `wave_creep_death team=2 kind=${kind} x=${x} y=${y} hp=0.05 by=${by} cid=${cid} lane=mid born=60 nd=0`);
const seen = (t, cid, by, tw, x = 0, y = 0, kind = 'melee') =>
    line(t, `creep_death team=3 kind=${kind} x=${x} y=${y} hp=0.05 by=${by} tw=${tw} cid=${cid}`);

test('a creep both teams logged is one row; the enemy hero that took it is named through the pairing, not by the owner', () => {
    // the owner's near-hero line (own_creep_death) of the same creep is the same unit as its wave line
    const { view, named, lastGame, game1, game2 } = run([wave(100, 7, 'none'), line(100, 'own_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none cid=7'), seen(100.2, 3, 5, 0, 40, 0)]);
    // `like` alone reads the log's last game, `game` is its number in the log (a log with one game has no game 2), `game_id` the store's
    assert.strictEqual(game2.length, 0);
    for (const rows of [view, named, lastGame, game1]) {
        assert.strictEqual(rows.length, 1);
        const r = rows[0];
        assert.deepStrictEqual([r.uid, r.kind, r.team, r.type, r.lane, r.wave, r.t0, r.x1, r.src], ['2:7', 'lane', 2, 'melee', 'mid', 2, 60, 0, 'log']);
        assert.deepStrictEqual([r.by_kind, r.by_pid, r.by_src], ['hero', 5, 'paired']);
    }
});

test('pairing is by kind, 1 s (not 2.5) and 250 units (not 300), and mutual: the nearer creep takes the sighting, the other stays unknown', () => {
    const { view } = run([
        wave(100, 7, 'none', 0, 0), wave(100.1, 8, 'none', 200, 0),
        seen(100.2, 3, 5, 0, 150, 0),
        // too far (300), and a ranged sighting of a melee death: neither pairs
        wave(200, 9, 'none', 0, 0), seen(200, 4, 6, 0, 300, 0),
        wave(300, 10, 'none', 0, 0), seen(300, 5, 6, 0, 0, 0, 'ranged'),
        // 2.5 s apart
        wave(400, 11, 'none', 0, 0), seen(402.5, 6, 6, 0, 0, 0),
    ]);
    const by = Object.fromEntries(view.filter(r => !r.uid.includes(':x')).map(r => [r.uid, r.by_pid]));
    assert.deepStrictEqual(by, { '2:7': null, '2:8': 5, '2:9': null, '2:10': null, '2:11': null });
    assert.strictEqual(view.filter(r => r.uid.includes(':x')).length, 3);
});

test('a deny is the owner hero, read from the owner own line; a tower kill needs the taker\'s tw and no hero', () => {
    const { view } = run([
        wave(100, 7, 1),
        wave(200, 8, 'none'), seen(200, 3, 'none', 1),
        wave(300, 9, 'none'), seen(300, 4, 'none', 0),
    ]);
    const r = Object.fromEntries(view.map(r => [r.uid, [r.by_kind, r.by_pid, r.by_src]]));
    assert.deepStrictEqual(r['2:7'], ['deny', 1, 'own']);
    assert.deepStrictEqual(r['2:8'], ['tower', null, 'paired']);
    assert.deepStrictEqual(r['2:9'], ['unknown', null, null]);
});

test('a creep only the enemy saw is a row owned by the other team, with the lane of its spot; a cid repeated by sight loss is one unit, the last line', () => {
    const { view } = run([
        // cid 3 leaves sight twice at low health before it dies for real at the last line (bot lane spot, 5000 -5500)
        seen(100, 3, 'none', 0, 4000, -4500), seen(101, 3, 'none', 0, 4500, -5000), seen(103, 3, 6, 0, 5000, -5500),
    ]);
    assert.strictEqual(view.length, 1);
    assert.deepStrictEqual([view[0].uid, view[0].team, view[0].lane, view[0].t1, view[0].t0, view[0].by_kind, view[0].by_pid, view[0].by_src],
        ['2:x3', 2, 'bot', 103, null, 'hero', 6, 'taker']);
});

test('a neutral both teams logged is one row, its camp and taker kept; two heroes taking neutrals at once are two', () => {
    const { view } = run([
        line(50, 'neutral_death team=2 kind=neutral x=3978 y=-5027 hp=0.05 by=1 camp=1'),
        line(50.3, 'neutral_death team=3 kind=neutral x=3990 y=-5000 hp=0.05 by=none camp=1'),
        line(80, 'neutral_death team=2 kind=neutral x=100 y=100 hp=0.05 by=1'),
        line(80.2, 'neutral_death team=3 kind=neutral x=110 y=100 hp=0.05 by=6'),
    ]);
    const n = view.filter(r => r.kind === 'neutral');
    assert.deepStrictEqual(n.map(r => [r.team, r.camp, r.by_kind, r.by_pid, r.t1]), [[4, 1, 'hero', 1, 50], [4, null, 'hero', 1, 80], [4, null, 'hero', 6, 80.2]]);
    assert.strictEqual(new Set(n.map(r => r.uid)).size, 3);
});

test('a log from before cid (and before the wave event) still reads: its own deaths and sightings are rows, no cid needed', () => {
    const { view } = run([
        line(100, 'own_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none'),
        line(100.2, 'creep_death team=3 kind=melee x=30 y=0 hp=0.05 by=5 tw=0'),
        line(200, 'creep_death team=3 kind=ranged x=0 y=0 hp=0.05 by=none tw=0'),
    ]);
    assert.deepStrictEqual(view.map(r => [r.uid.replace(/\d+$/, '#'), r.type, r.by_kind, r.by_pid, r.t0, r.wave]),
        [['2:e#', 'melee', 'hero', 5, null, null], ['2:xe#', 'ranged', 'unknown', null, null, null]]);
});
