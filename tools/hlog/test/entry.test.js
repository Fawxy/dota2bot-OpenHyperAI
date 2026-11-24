'use strict';
// The entry point of hlog (scene-and-unit-lives proposal s6): the usage's five questions, `q @unit`, and the foot of a scene.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { Store } = require('../store');
const { ingestReplay } = require('../replay');
const { secs, timelineRows } = require('../hlog');
const { scene } = require('../scene');

const HLOG = path.join(__dirname, '..', 'hlog.js');
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sqlOf = n => fs.readFileSync(path.join(__dirname, '..', 'queries', `${n}.sql`), 'utf8');
const camp = { x: 4649, y: -3699 };

function open(name, lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-entry-'));
    const file = path.join(dir, `2026-11-25T00-00-00-${name}.log`);
    fs.writeFileSync(file, `${lines.join('\n')}\n`);
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return { store, file, gameId: store.query('SELECT game_id FROM games')[0].game_id };
}

// A hero 300 from a camp for 40 s, with two own lane creeps dying there (cid 8 first, nobody's; cid 9 denied by the hero).
const game = () => open('e_A_rad_1', [
    line(-90, 'bot pid=0 hero=luna team=2 pos=1'),
    ...Array.from({ length: 41 }, (_, i) => line(160 + i, `snap pid=0 x=${camp.x + 300} y=${camp.y} alive=1 hp=90 ln=bot s=0.5 ld=40 mode=farm`)),
    line(170, `wave_creep_death team=2 kind=melee x=${camp.x} y=${camp.y} hp=0.05 by=none cid=8 lane=bot born=60 nd=0`),
    line(175, `wave_creep_death team=2 kind=melee x=${camp.x} y=${camp.y} hp=0.05 by=0 cid=9 lane=bot born=60 nd=0`),
]);
const scene1 = ({ store, file }, target) => scene(store, file, { pid: 0, from: '2:45', to: '3:15', every: 10 }, { secs, timelineRows, target }).lines;
const footer = lines => lines.slice(lines.indexOf('next:') + 1).map(l => l.trim());

test('usage: the five questions come first, in order, on no arguments (stderr, exit 2) and on --help (stdout, exit 0)', () => {
    const bare = spawnSync(process.execPath, [HLOG], { encoding: 'utf8' });
    const help = spawnSync(process.execPath, [HLOG, '--help'], { encoding: 'utf8' });
    assert.strictEqual(bare.status, 2);
    assert.strictEqual(bare.stdout, '');
    assert.strictEqual(help.status, 0);
    assert.strictEqual(help.stderr, '');
    assert.strictEqual(help.stdout.trimEnd(), bare.stderr.trimEnd());
    const at = ['hlog.js digest <log>', 'hlog.js scene <log> --at', 'hlog.js q @unit --p like=<label> --p uid=<uid>', 'timeline <batch> --count', 'hlog.js list [word]']
        .map(s => bare.stderr.indexOf(s));
    assert.ok(at.every(i => i >= 0), `a question is missing: ${at}`);
    assert.deepStrictEqual([...at].sort((a, b) => a - b), at, 'in the order of the proposal');
    assert.ok(at[4] < bare.stderr.indexOf('node hlog.js ingest'), 'before the subcommand usage');
});

test('q @unit: a recorded unit has its life, its path and the hits it took and dealt, matched by kind, team and name inside its life', () => {
    const { store, file, gameId } = game();
    const u = (uid, t0, extra) => ({ k: 'unit', uid, ent: Number(uid.split('.')[0]), kind: 'lane', team: 3, type: 'melee', name: 'npc_dota_creep_badguys_melee', t0, x0: 0, y0: 0, maxhp: 500, end: 'alive', ...extra });
    const hit = (t, ak, tk, dmg, extra) => ({ k: 'hit', t, ak, at: ak === 'hero' ? 2 : 3, an: ak === 'hero' ? 'npc_dota_hero_luna' : 'npc_dota_creep_badguys_melee', tk, tt: tk === 'hero' ? 2 : 3,
        tn: tk === 'hero' ? 'npc_dota_hero_luna' : 'npc_dota_creep_badguys_melee', dmg, inf: '', ...extra });
    ingestReplay(store, gameId, 'e.dem', [
        u('81.0', 100, { end: 'death', t1: 130, x1: 9, y1: 9, hp: 5, by_kind: 'hero', by_pid: 0, kdt: 0 }),
        u('82.0', 110),
        ...[100, 101, 102].map(t => ({ k: 'pos', t, u: [['81.0', t, -t, 400]] })),
        hit(105, 'hero', 'lane', 50, { ap: 0 }), // only 81.0 is alive
        hit(120, 'hero', 'lane', 60, { ap: 0 }), hit(125, 'lane', 'hero', 20, { tp: 0 }), // a D melee hit luna: either again
        hit(140, 'hero', 'lane', 70, { ap: 0 }), // after 81.0 died: not its hit
        { k: 'meta', until: 720, players: [] }, { k: 'end', netTick: 1, t: 720, deathEntries: 0, deathMatched: 0 },
    ]);
    const rows = store.query(sqlOf('unit'), { like: file, uid: '81.0' });
    assert.deepStrictEqual(rows.map(r => r.part), ['life', 'pos', 'pos', 'pos', 'hit', 'hit', 'hit']);
    assert.match(rows[0].detail, /uid=81\.0 .*t1=130 .*by=hero:0 .*from=replay/);
    assert.deepStrictEqual(rows.filter(r => r.part === 'pos').map(r => [r.t, r.x, r.y, r.hp]), [[100, 100, -100, 400], [101, 101, -101, 400], [102, 102, -102, 400]]);
    assert.deepStrictEqual(rows.filter(r => r.part === 'hit').map(r => [r.t, r.dir, r.other, r.dmg, r.n_like]),
        [[105, 'taken', '0 luna', 50, 1], [120, 'taken', '0 luna', 60, 2], [125, 'dealt', '0 luna', 20, 2]]);
});

test('q @unit: a unit of a game with no replay rows has its life row only, read from the log', () => {
    const g = game();
    const rows = g.store.query(sqlOf('unit'), { like: g.file, uid: '2:9' });
    assert.deepStrictEqual(rows.map(r => r.part), ['life']);
    assert.match(rows[0].detail, /uid=2:9 kind=lane team=2 type=melee .*by=deny:0 .*from=log/);
    assert.deepStrictEqual(g.store.query(sqlOf('unit'), { like: g.file, uid: '2:99' }), []);
});

test('the foot of a scene: the unit a hero on screen took, the window on the timeline, and replay only with a .dem beside the log and no replay rows', () => {
    const g = game();
    let foot = footer(scene1(g, 'e_A_rad_1'));
    assert.strictEqual(foot.length, 2, 'no .dem: unit and timeline only');
    assert.strictEqual(foot[0], 'node hlog.js q @unit --p like=e_A_rad_1 --p uid=2:9', 'the denied creep, not the earlier one nobody took');
    assert.match(foot[1], /^node hlog\.js timeline e_A_rad_1 --from 2:45 --to 3:15 --hero luna$/);
    fs.writeFileSync(g.file.replace(/\.log$/, '.dem'), 'x');
    foot = footer(scene1(g, 'e_A_rad_1'));
    assert.deepStrictEqual(foot.map(l => l.split(' ').slice(0, 3).join(' ')), ['node hlog.js q', 'node hlog.js timeline', 'node hlog.js replay']);
    ingestReplay(g.store, g.gameId, 'e.dem', [{ k: 'meta', until: 720, players: [] }, { k: 'end', netTick: 1, t: 720, deathEntries: 0, deathMatched: 0 }]);
    assert.ok(!footer(scene1(g, 'e_A_rad_1')).some(l => l.includes(' replay ')), 'a read game needs no replay');
    const quiet = scene(g.store, g.file, { pid: 0, from: '3:40', to: '3:50', every: 10 }, { secs, timelineRows, target: 'e_A_rad_1' }).lines;
    assert.ok(!footer(quiet).some(l => l.includes('@unit')), 'no unit died in that window: no unit to name');
});
