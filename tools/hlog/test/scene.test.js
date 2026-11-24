'use strict';
// `hlog.js scene` (scene.js): heroes in the scene, distance to the own team's front, tower range, event lines, the refusals.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { Store } = require('../store');
const { secs, timelineRows } = require('../hlog');
const { scene, LANE_LEN, LANE_TOWERS } = require('../scene');
const { C } = require('../dynamic');

const T1 = LANE_TOWERS.find(t => t.team === 2 && t.lane === 'bot' && t.tier === 1); // (4860, -6379)
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

/**
 * Bot lane at Radiant's tier 1 tower. luna (R1) 699 from the tower, lich (R5) 701; axe (D1) 700 from it, ogre (D5) in mid, jakiro (D4) far
 * up the bot lane. Radiant's front is at s 0.55, Dire's at 0.60 (each team has its own frame): luna 0.50 and axe 0.52.
 * luna attacks 101-104 and casts at 102; her last hit at 102.5, a creep nobody got at 103 and a neutral at 103.5 are near, one creep far off.
 * The tower falls at 103.
 */
function logLines() {
    const out = [
        line(-90, 'bot pid=0 hero=luna team=2 pos=1'), line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=axe team=3 pos=1'), line(-90, 'bot pid=6 hero=ogre_magi team=3 pos=5'), line(-90, 'bot pid=8 hero=jakiro team=3 pos=4'),
    ];
    const snap = (t, pid, x, y, ln, s, extra = '') => out.push(line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=90 ln=${ln} s=${s} ld=40 ${extra}`));
    for (let t = 95; t <= 110; t++) {
        const attack = t >= 101 && t <= 104;
        snap(t, 0, T1.x, T1.y + 699, 'bot', 0.5, `mode=${attack ? 'attack' : 'laning'} by="${attack ? 'attack (valve)' : 'laning 0.5 by raw'}" tid=h5 tgt=npc_dota_hero_axe`);
        snap(t, 1, T1.x, T1.y + 701, 'bot', 0.5, 'mode=laning');
        snap(t, 5, T1.x + 700, T1.y, 'bot', 0.52, 'mode=laning tid=u7 tgt=npc_dota_creep_goodguys_melee');
        snap(t, 6, -1000, -1000, 'mid', 0.5, 'mode=laning');
        snap(t, 8, 6300, 2900, 'bot', 0.9, 'mode=laning');
    }
    for (let t = 95; t <= 110; t++) {
        out.push(line(t + 0.1, `front team=2 top=0.4 topx=-6300 topy=1800 mid=0.5 midx=-1500 midy=-1400 bot=0.55 botx=${T1.x + 140} boty=${T1.y + 80}`));
        out.push(line(t + 0.1, `front team=3 top=0.5 topx=-5000 topy=6000 mid=0.6 midx=500 midy=600 bot=0.6 botx=${T1.x + 540} boty=${T1.y + 80}`));
    }
    out.push(line(102, 'cast pid=0 ab=luna_lucent_beam'));
    out.push(line(102.5, `creep_death team=2 kind=ranged x=${T1.x} y=${T1.y + 600} hp=0 by=0 tw=0 cid=1`));
    out.push(line(103, `creep_death team=3 kind=melee x=${T1.x + 50} y=${T1.y + 650} hp=0 by=none tw=0 cid=2`));
    out.push(line(103, `creep_death team=2 kind=melee x=-3000 y=0 hp=0 by=none tw=0 cid=3`));
    out.push(line(103.5, `neutral_death team=2 kind=neutral x=${T1.x + 60} y=${T1.y + 700} hp=0 by=none camp=3 np=1 nd=1`));
    out.push(line(103, 'building_fall team=2 kind=tower id=6 tier=1'));
    out.push(line(730, 'snap pid=0 x=0 y=0 alive=1 hp=90 ln=mid s=0.5 ld=40 mode=laning'));
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

function open() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-scene-'));
    const file = path.join(dir, '2026-11-25T00-00-00-scn_A_rad_1.log');
    fs.writeFileSync(file, logLines().join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return { store, file: path.resolve(file), dir };
}

const run = (store, file, o) => scene(store, file, o, { secs, timelineRows, target: 'scn_A_rad_1' });
const heroRows = (r, t) => r.rows.filter(x => x.kind === 'hero' && x.t === t);

test('scene: a hero scene holds the hero and every hero within the radius, and nothing else', () => {
    const { store, file } = open();
    const wide = run(store, file, { pid: 0, at: '1:40' });
    assert.deepStrictEqual(heroRows(wide, 100).map(h => h.hero), ['luna', 'lich', 'axe']);
    const tight = run(store, file, { hero: 'luna', at: '1:40', r: 900 });
    assert.deepStrictEqual(heroRows(tight, 100).map(h => h.hero), ['luna', 'lich'], 'axe is 989 away');
    assert.strictEqual(heroRows(wide, 100)[0].enemy_pid, 5);
    assert.strictEqual(heroRows(wide, 100)[0].enemy_d, 989);
});

test('scene: the distance to the front is read against the hero\'s own team front, in lane lengths', () => {
    const { store, file } = open();
    assert.ok(Math.abs(LANE_LEN.bot - 22701.7) < 1, 'the bot lane polyline, ancient to ancient');
    const r = run(store, file, { pid: 0, at: '1:40' });
    const [luna, , axe] = heroRows(r, 100);
    assert.strictEqual(luna.front_ahead, -Math.round(0.05 * LANE_LEN.bot), 'Radiant s 0.50 against its front 0.55: behind');
    assert.strictEqual(axe.front_ahead, Math.round(0.08 * LANE_LEN.bot), 'Dire s 0.52 against its front 0.60: ahead, in Dire\'s frame');
    assert.deepStrictEqual(r.rows.find(x => x.kind === 'front'), { t: 100, kind: 'front', lane: 'bot', rad_s: 0.55, dire_s: 0.6, gap: 400 });
});

test('scene: a hero is under a tower within its range only, and not after the tower falls', () => {
    const { store, file } = open();
    assert.strictEqual(C.TOWER_R, 700);
    const r = run(store, file, { pid: 0, from: '1:40', to: '1:50' });
    const at = t => Object.fromEntries(heroRows(r, t).map(h => [h.hero, h.tower]));
    assert.deepStrictEqual(at(100), { luna: 'own T1 bot', lich: null, axe: 'enemy T1 bot' }, '699 and 700 in, 701 out');
    assert.deepStrictEqual(at(105), { luna: null, lich: null, axe: null }, 'building_fall at 103');
});

test('scene: a lane scene takes the heroes on that lane near either front', () => {
    const { store, file } = open();
    const r = run(store, file, { lane: 'bot', at: '1:40' });
    assert.deepStrictEqual(heroRows(r, 100).map(h => h.hero), ['luna', 'lich', 'axe'], 'ogre is in mid, jakiro 9,000 up the lane');
});

test('scene: a point scene takes the heroes within the radius of the point', () => {
    const { store, file } = open();
    const r = run(store, file, { xy: `${T1.x},${T1.y + 699}`, r: 100, at: '1:40' });
    assert.deepStrictEqual(heroRows(r, 100).map(h => h.hero), ['luna', 'lich']);
});

test('scene: between frames come the timeline rows of the heroes shown and the deaths inside the radius', () => {
    const { store, file } = open();
    const r = run(store, file, { pid: 0, from: '1:40', to: '1:50' });
    const tl = r.rows.filter(x => x.kind === 'timeline').map(x => [x.hero, x.what, x.t]);
    assert.ok(tl.some(([h, k, t]) => h === 'luna' && k === 'cast' && t === 102));
    assert.ok(tl.some(([h, k, t]) => h === 'luna' && k === 'mode' && t === 101));
    assert.deepStrictEqual(r.rows.filter(x => x.kind === 'creep' || x.kind === 'neutral').map(x => [x.t, x.kind, x.team ?? null, x.fate ?? null, x.pid]),
        [[102.5, 'creep', 3, 'own_lh', 0], [103, 'creep', 2, 'other', null], [103.5, 'neutral', null, null, null]], 'the creep at (-3000, 0) is outside the radius');
    const text = r.lines.join('\n');
    assert.match(text, /1:42 +D ranged died \(4860,-5779\): last hit by R1 luna/);
    assert.match(text, /neutral died .* camp 3: no hero credited/);
});

test('scene: a lone frame reads the events a frame (--every) either side, and the header says what the log cannot know', () => {
    const { store, file } = open();
    const times = o => run(store, file, { pid: 0, at: '1:44', ...o }).rows.filter(x => x.kind === 'creep' || x.kind === 'neutral').map(x => x.t);
    assert.deepStrictEqual(times({ every: 1 }), [103, 103.5], '102.5 is more than 1 s before');
    assert.deepStrictEqual(times({}), [102.5, 103, 103.5]);
    const r = run(store, file, { pid: 0, at: '1:44' });
    assert.strictEqual(r.rows.filter(x => x.kind === 'hero').length, 3, 'one frame');
    assert.match(r.lines[1], /not known in an unrecorded game/);
});

test('scene: a timeline row that began before the window and overlaps it is kept, at its own start', () => {
    const { store, file } = open();
    const r = run(store, file, { pid: 0, at: '1:44', every: 1 });
    const mode = r.rows.find(x => x.kind === 'timeline' && x.what === 'mode' && x.hero === 'luna');
    assert.deepStrictEqual([mode?.t, mode?.t1], [101, 104], 'attack 101-104 against the window 103-105');
    assert.match(r.lines.join('\n'), /1:41-1:44 +R1 luna +mode +attack/);
    assert.ok(!r.rows.some(x => x.kind === 'timeline' && x.what === 'cast'), 'the cast at 102 ended before the window');
});

test('scene: a hero with no frame says whether it is dead or the log has ended', () => {
    const { store, file } = open();
    const note = o => run(store, file, o).rows.find(x => x.kind === 'note')?.text;
    assert.strictEqual(note({ pid: 0, at: '13:00' }), 'the log ends at 12:10');
    assert.match(note({ hero: 'jakiro', at: '2:00' }), /dead \(no snapshot since 1:50, at \(6300,2900\)\)/);
    assert.match(note({ hero: 'jakiro', at: '3:00' }), /dead \(no snapshot since 1:50/, 'none in the window: read from before it');
});

test('scene: after 12:00 the header says no unit is logged', () => {
    const { store, file } = open();
    const r = run(store, file, { pid: 0, at: '12:10' });
    assert.match(r.lines[0], /no unit is logged after 12:00/);
    assert.strictEqual(scene(store, file, { pid: 0, at: '1:40' }, { secs, timelineRows, target: 'x' }).lines[0].includes('no unit is logged'), false);
});

test('scene: refusals print the narrower command, and a wrong option is an error', () => {
    const { store, file } = open();
    assert.throws(() => run(store, file, { pid: 0, from: '1:40', to: '3:10' }), /over 60 s.*--from 1:40 --to 2:40 --pid 0/);
    assert.throws(() => run(store, file, { pid: 0, from: '1:35', to: '1:50', every: 1, r: 9000 }), /over 80.*--from 1:35 --to 1:42 --pid 0 --r 9000 --every 1/);
    assert.throws(() => run(store, file, { hero: 'lunna', at: '1:40' }), /no hero lunna.*luna/);
    assert.throws(() => run(store, file, { at: '1:40' }), /needs one of --hero/);
    assert.throws(() => run(store, file, { pid: 0, lane: 'bot', at: '1:40' }), /needs one of --hero/);
    assert.throws(() => run(store, file, { pid: 0, at: '1:40', from: '1:30' }), /not both/);
    assert.throws(() => run(store, file, { lane: 'base', at: '1:40' }), /no lane base/);
    assert.throws(() => run(store, file, { xy: '12', at: '1:40' }), /not x,y/);
});

test('scene: the command line prints the text and, with --json, the same rows', () => {
    const { file, dir } = open();
    const hlog = path.join(__dirname, '../hlog.js');
    const args = ['scene', file, '--db', path.join(dir, 'x.sqlite'), '--pid', '0', '--at', '1:40'];
    const text = spawnSync('node', [hlog, ...args], { encoding: 'utf8' });
    assert.strictEqual(text.status, 0, text.stderr);
    assert.match(text.stdout, /1:40 .*\n.*R1 luna +\(4860,-5680\) +bot s=0.50 +1135 behind front +hp 90 +laning 0.5 by raw +-> D1 axe/);
    assert.match(text.stdout, /next:\n( {2}node hlog.js q @unit .*\n)? {2}node hlog.js timeline /);
    const json = spawnSync('node', [hlog, ...args, '--json', '--no-ingest'], { encoding: 'utf8' });
    const o = JSON.parse(json.stdout);
    assert.deepStrictEqual(o.rows.filter(r => r.kind === 'hero').map(r => r.hero), ['luna', 'lich', 'axe']);
    assert.strictEqual(o.header.game, 1);
});
