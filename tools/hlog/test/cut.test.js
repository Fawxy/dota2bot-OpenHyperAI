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
