'use strict';
// The rune spawn reader (queries/rune_spawns.sql): one row per spawn from the rule's times, and who took it.
// Radiant luna (pid 0, pos 2) and lich (pid 1, pos 5); Dire sniper (pid 5, pos 2), on a synthetic game.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const SPOT = { 0: [-1640, 1112], 1: [1180, -1216], 2: [-997, 4431], 3: [595, -4660] };
const pick = (t, pid, team, rune, kind) =>
    line(t, `rune_pickup pid=${pid} team=${team} rune=${rune} kind=${kind} x=${SPOT[rune][0]} y=${SPOT[rune][1]}`);

/**
 * 0.5   a pickup before tracking starts (the 0:00 bounty): not a spawn of the reader's
 * 2:00  water: bot spot taken by sniper at once; top spot untaken
 * 4:00  water: top taken by luna at 250 (a second pickup there at 300 is not that spawn's first); bot untaken.
 *       bounty: Radiant's jungle (3) taken by lich at 400 (own); Dire's (2) untaken
 * 6:00  power, taken on the bot spot by sniper at 361
 * 8:00  power untaken (its spot unknown); bounty: Dire's jungle taken by lich at 500 (not own); Radiant's untaken
 */
function gameLines() {
    return [
        line(-90, 'bot pid=0 hero=luna team=2 pos=2'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=sniper team=3 pos=2'),
        pick(0.5, 1, 2, 3, 'bounty'),
        pick(120.5, 5, 3, 1, 'water'),
        pick(250, 0, 2, 0, 'water'),
        pick(300, 0, 2, 0, 'water'),
        pick(361, 5, 3, 1, 'power'),
        pick(400, 1, 2, 3, 'bounty'),
        pick(500, 1, 2, 2, 'bounty'),
        line(700, 'snap pid=0 x=0 y=0 alive=1 hp=100'),
    ];
}

test('rune_spawns: each spawn before :until with its first pickup in the window, untaken otherwise', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rune-sp-'));
    const file = path.join(dir, '2026-11-24T00-00-00-rs_A_off_1.log');
    fs.writeFileSync(file, gameLines().join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'rune_spawns.sql'), 'utf8');
    const rows = store.query(sql, { like: '%rs_A_off_1%', until: 600 }).map(r => ({ ...r }));
    const got = rows.map(r => [r.kind, r.sp, r.rune, r.side, r.res, r.pid, r.pos, r.dt, r.own]);
    assert.deepStrictEqual(got, [
        ['water', 120, 0, 'river', 'untaken', null, null, null, null],
        ['water', 120, 1, 'river', 'taken', 5, 2, 0.5, null],
        ['bounty', 240, 2, 'dire', 'untaken', null, null, null, null],
        ['bounty', 240, 3, 'rad', 'taken', 1, 5, 160, 1],
        ['water', 240, 0, 'river', 'taken', 0, 2, 10, null],
        ['water', 240, 1, 'river', 'untaken', null, null, null, null],
        ['power', 360, 1, 'river', 'taken', 5, 2, 1, null],
        ['bounty', 480, 2, 'dire', 'taken', 1, 5, 20, 0],
        ['bounty', 480, 3, 'rad', 'untaken', null, null, null, null],
        ['power', 480, null, 'river', 'untaken', null, null, null, null],
    ]);
});
