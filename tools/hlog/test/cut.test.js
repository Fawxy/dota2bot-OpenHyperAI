'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { readGames, worldOf, checkOne } = require('../cut');

const hev = (s) => `11/13 15:33:39 [VScript] [HEV] ${s}`;
// Smoke 1's shape: the towers line is written in the pregame, and a clock jump to 0:00 later splits the log's games.
const LOG = [
    hev('t=-90.000 ev=bot pid=1 team=2 ours=LaneSpot:1,LaneSpotThreat:1,LaneSpotTower:1'),
    hev('t=-14.800 ev=cut_towers team=2 tw=0,-6336,1856,700,144;3,-1544,-1408,700,144'),
    hev('t=-14.800 ev=cut_towers team=3 tw=3,524,652,700,144;6,6269,-2240,700,144'),
    hev('t=-60.000 ev=snap pid=1'),
    hev('t=200.000 ev=cut pid=1 kind=spot role=core lane=2 b=-2000,-1800,500,600,600,24,300,0 fr=-1200,-1000,-1500,-1250 '
        + 'he=6,-900,-700,550,500,24,290,1,0,120,240,0 hu=7,3000,2000,12.5,305 ta=9,8 tt=2,3,h6 '
        + 'vis=-3600,-3400,14,12,250,ffff'),
    hev('t=200.000 ev=cut_creeps pid=1 ce=11,-1100,-900,300,550,0,u12,16 ca=12,-1250,-1050,400,550,1,u11,16'),
].join('\n');

test('a towers line from before a clock jump still serves the game after it, and dead towers drop out by the mask', () => {
    const games = readGames(LOG);
    assert.strictEqual(games.length, 2);
    const g = games[1];
    const w = worldOf(g, g.cuts[0]);
    // Ours: mask 9 keeps indices 0 and 3; theirs: mask 8 keeps index 3 only (their tower 6 has fallen).
    assert.deepStrictEqual(w.towers.map((t) => `${t.team}:${t.i}`), ['2:0', '2:3', '3:3']);
    assert.strictEqual(w.towers.find((t) => t.team === 2 && t.i === 3).tgt, 'h6');
    assert.strictEqual(w.team, 2);
    assert.strictEqual(w.ours.LaneSpotThreat, true);
});

test('the world carries every record the driver serves: engaged hero, unseen hero, creep targets, the grid', () => {
    const g = readGames(LOG)[1];
    const w = worldOf(g, g.cuts[0]);
    assert.deepStrictEqual(w.he[0], { pid: 6, x: -900, y: -700, hp: 550, range: 500, hull: 24, speed: 290, atk: 1, eng: 0, e3: 120, e6: 240, ill: 0 });
    assert.deepStrictEqual(w.hu[0], { pid: 7, x: 3000, y: 2000, tss: 12.5, sp: 305 });
    assert.strictEqual(w.ce[0].tgt, 'u12');
    assert.strictEqual(w.ca[0].ranged, 1);
    // A grid of digits stays a string (parse.js would turn it into a number and drop its zeros).
    assert.deepStrictEqual(w.vis, { x0: -3600, y0: -3400, nx: 14, ny: 12, step: 250, hex: 'ffff' });
});

test('a cut missing its creeps line is reported, not replayed on a world without creeps', () => {
    const g = readGames(LOG.split('\n').filter((l) => !l.includes('cut_creeps')).join('\n'))[1];
    assert.throws(() => worldOf(g, g.cuts[0]), /no ev=cut_creeps/);
    assert.match(checkOne(g, g.cuts[0]).error, /no ev=lane_pos|no ev=cut_creeps/);
});

// Gate cuts: a Radiant core at (-200, 200) walking to a camp at (800, 900), a tower pair that puts the camp next to the
// enemy's (depth well under 0.5, so an unseen hero counts its full late weight of 0.5, the refusal line).
const gateLog = ({ he = '', hu = '', vw = '', dec = 'go', who = 'core_camp', t = '300.000' }) => [
    hev('t=-90.000 ev=bot pid=1 team=2 ours=Threat:1'),
    hev('t=-14.800 ev=cut_towers team=2 tw=3,-1544,-1408,700,144'),
    hev('t=-14.800 ev=cut_towers team=3 tw=3,524,652,700,144'),
    hev(`t=${t} ev=threat pid=1 who=${who} dec=${dec}`),
    hev(`t=${t} ev=cut pid=1 kind=gate who=${who} b=-200,200,600,600,150,24,300,0 fm=-200,200 pl=800,900 he=${he || '""'} ta=8,8`
        + (hu ? ` hu=${hu}` : '') + (vw ? ` vw=${vw}` : '')),
].join('\n');
const gateGame = (opts) => readGames(gateLog(opts))[0];
const UNSEEN = '7,1500,1500,10,305';

test('a visible hero able to reach the walk holds the trip as threat; one too far to reach does not', () => {
    // 330 speed over 4 s, plus range and hulls, is about 2,000: a hero 1,100 from the walk reaches it, one 4,000 away cannot.
    const near = gateGame({ he: '6,1500,-100,500,600,24,330,0,0,100,200,0', dec: 'threat' });
    const r = checkOne(near, near.cuts[0]);
    assert.deepStrictEqual([r.got, r.same, r.reach], ['threat', true, 1]);
    const far = gateGame({ he: '6,4800,-3000,500,600,24,330,0,0,100,200,0', dec: 'go' });
    const f = checkOne(far, far.cuts[0]);
    assert.deepStrictEqual([f.got, f.same, f.reach], ['go', true, 0]);
});

test('an unseen hero holds the trip as missing only while part of the walk it could reach is out of sight', () => {
    const blind = gateGame({ hu: UNSEEN, vw: '4,e8', dec: 'missing' });
    const b = checkOne(blind, blind.cuts[0]);
    assert.deepStrictEqual([b.got, b.same, b.missing], ['missing', true, 0.5]);
    // The same hero with every walk point in sight is not there: the vision cut drops it and the gate goes.
    const seen = gateGame({ hu: UNSEEN, vw: '4,f8', dec: 'go' });
    const s = checkOne(seen, seen.cuts[0]);
    assert.deepStrictEqual([s.got, s.same, s.missing], ['go', true, 0]);
});

test('a replay that decides otherwise than the game is reported as different, not forced to match', () => {
    const g = gateGame({ hu: UNSEEN, vw: '4,e8', dec: 'go' });
    const r = checkOne(g, g.cuts[0]);
    assert.deepStrictEqual([r.same, r.got, r.want], [false, 'missing', 'go']);
});

test('gate cuts join their ev=threat by consumer: two consumers deciding in one frame are each checked against their own', () => {
    const text = gateLog({ hu: UNSEEN, vw: '4,e8', dec: 'missing', who: 'core_camp' }) + '\n'
        + hev('t=300.000 ev=threat pid=1 who=pull_farm dec=go') + '\n'
        + hev('t=300.000 ev=cut pid=1 kind=gate who=pull_farm b=-200,200,600,600,150,24,300,0 fm=-200,200 pl=800,900 he="" ta=8,8 hu=' + UNSEEN + ' vw=4,e8');
    const g = readGames(text)[0];
    const res = Object.fromEntries(g.cuts.map((c) => [c.who, checkOne(g, c).same]));
    assert.deepStrictEqual(res, { core_camp: true, pull_farm: false });
});
