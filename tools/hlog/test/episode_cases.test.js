'use strict';
// (A job row's times are rounded to 0.1 s.)
// Each episode kind pinned to real moments (fixtures in test/data/episodes), read by hand from the raw log lines and the stated rule of
// its fragment (queries/fragments/ep_*.sql header) BEFORE the timeline was run on them. Two readings disagreed with the timeline on
// how a break is counted; the fragments' headers now say it in seconds apart, and those cases pin the edge.
//
// The fixtures are cuts of Dota logs from ~/.dotactl/logs, named by their run label: telemetry lines only (the first ev=bot line of
// each hero, the snapshots of the heroes the cases read reduced to pid x y alive hp deaths mode tid, and the job lines of the cases).
// A hero's cut runs on to its first snapshot after a rise of its deaths counter, so a death is dated as in the full log. A cut ends
// or starts mid-game, so a fixture also holds episodes that are not in the game (a hero whose snapshots stop reads as dead at the
// log's end); only the cases below are asserted. The row of each case was checked equal in the cut and in the full log.
//   h2hlift1_A_off-rad_1  game 2 of that log; snapshots: all heroes 232-262 s; jakiro -91-245 s; zuus -91-250 s; jakiro and bounty_hunter 512-532 s; jobs of pids 3, 4, 6 at 150-180 s
//   base1_A_stock_1       a stock game: only Radiant logs; luna 305-329 s, pudge 140-170 s and 530-570 s, sniper 90-110 s
//   h2hlift1_B_off-dir_4  warlock, tiny 308-325 s; skeleton_king 300-330 s
//   h2hlift1_B_off-rad_10 witch_doctor, bristleback, lich 262-285 s
//   h2hlift1_A_off-dir_3  farm trips of luna at 690-800 s
// Stock logs have no job lines, so job has no stock case. A stock log has no Dire snapshots either, so a Dire hero is no one in it: so
// a stock hero's attacks on one make no exchange and no kill_try, and neither kind has a stock case (base1's stock games; a stock
// game with both sides logging has them).
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { Store } = require('../store');
const { timelineRows } = require('../hlog');

const DIR = path.join(__dirname, 'data', 'episodes');
const stores = new Map();
function rowsOf(label, o) {
    const file = path.join(DIR, `${label}.log`);
    if (!stores.has(label)) {
        const store = new Store(':memory:');
        store.ingest(file);
        store.refreshViews();
        stores.set(label, store);
    }
    return timelineRows(stores.get(label), path.resolve(file), o).filter(r => r.kind !== 'not_logged');
}
test.after(() => stores.forEach(s => s.close()));

const A1 = 'h2hlift1_A_off-rad_1';
const STOCK = 'base1_A_stock_1';
const attackers = r => (r.detail.match(/attacked by ([a-z_, ]+?)(;|$)/) || [])[1]?.split(', ').sort();

// ---- death ------------------------------------------------------------------------------------------------------------------

test('death: luna dies retreating, its attackers are those who hit it in the 10 s before', () => {
    // luna (pid 0) retreat at hp 2 at 248.17 and no snapshot after (rise at its respawn); bounty_hunter hits it (tid=h0) at 247 and 248, sand_king at 246-248
    const [d] = rowsOf(A1, { kind: 'death', hero: 'luna', from: '4:00', to: '4:10' });
    assert.ok(Math.abs(d.t - 248.17) < 0.06, `t ${d.t}`);
    assert.match(d.detail, /^died in retreat/);
    assert.deepStrictEqual(attackers(d), ['bounty_hunter', 'sand_king']);
    assert.strictEqual(d.side, 'test');
});

test('death: after a jump to the fountain the death is dated before the jump, at the last snapshot with HP above 0', () => {
    // skeleton_king (pid 7, Dire): hp 2 retreat at 322.13, hp 0 at 323.13, at its fountain (6910,6288) at 324.13 with hp 1, 7, 12, then nothing until deaths=1 at 343.53;
    // warlock hits it (tid=h7) at 316-319 and 321-323, tiny at 317-319 and 323
    const [d] = rowsOf('h2hlift1_B_off-dir_4', { kind: 'death', hero: 'skeleton_king', from: '5:00', to: '5:30' });
    assert.ok(Math.abs(d.t - 322.13) < 0.06, `t ${d.t}`);
    assert.match(d.detail, /^died in retreat/);
    assert.deepStrictEqual(attackers(d), ['tiny', 'warlock']);
});

test('death: a stock log dates the death at the last snapshot and names no attacker', () => {
    // luna (pid 0, Radiant, the only team logged) retreating at hp 8 at 329.00, no snapshot after; no Dire hero is logged, so no one is recorded as hitting it
    const [d] = rowsOf(STOCK, { kind: 'death', hero: 'luna', from: '5:20', to: '5:35' });
    assert.strictEqual(d.t, 329);
    assert.strictEqual(d.detail, 'died in retreat: unexplained');
    assert.strictEqual(d.side, null);
});

// ---- retreat ----------------------------------------------------------------------------------------------------------------

test('retreat: a stock bout of three seconds that was survived', () => {
    // pudge (pid 1) laning to 150, mode retreat at 151 (hp 72), 152 (72), 153 (66), team_roam from 154
    const [r] = rowsOf(STOCK, { kind: 'retreat', hero: 'pudge', from: '2:30', to: '2:35' });
    assert.deepStrictEqual([r.t, r.t1, r.hp0, r.hp1, r.hpmin, r.outcome], [151, 153, 72, 66, 66, 'lived']);
});

test('retreat: a 2 s break inside is one bout, and a death at its end makes it died', () => {
    // jakiro (pid 3) retreat 236-238, farm at 239 and 240, retreat 241-244 (hp 100 to 5), no snapshot after 244.17
    const r = rowsOf(A1, { kind: 'retreat', hero: 'jakiro', from: '3:50', to: '4:10' }).filter(x => x.hero === 'jakiro');
    assert.strictEqual(r.length, 1);
    assert.deepStrictEqual([r[0].t, r[0].t1, r[0].hp0, r[0].hp1, r[0].hpmin, r[0].outcome], [236, 244, 100, 5, 5, 'died']);
});

test('retreat: seconds 4 apart (a 3 s break) are two bouts', () => {
    // bounty_hunter (pid 7) retreat at 245 (hp 41), attack at 246, 247, 248, retreat at 249 (hp 43), laning at 250
    const r = rowsOf(A1, { kind: 'retreat', hero: 'bounty_hunter', from: '4:04', to: '4:10' }).filter(x => x.hero === 'bounty_hunter');
    assert.deepStrictEqual(r.map(x => [x.t, x.t1, x.hp0, x.hp1, x.outcome]), [[245, 245, 41, 41, 'lived'], [249, 249, 43, 43, 'lived']]);
});

// ---- exchange ---------------------------------------------------------------------------------------------------------------

test('exchange: answered, with the seconds each side attacked', () => {
    // luna (pid 0) targets bounty_hunter (h7) at 239, 240, 241, 243, 244; bounty_hunter targets luna (h0) at 247 and 248 (3 s after the last: the same exchange)
    const x = rowsOf(A1, { kind: 'exchange', hero: 'luna', from: '3:55', to: '4:10' }).find(r => r.hero === 'luna' && r.other === 'bounty_hunter');
    assert.deepStrictEqual([x.t, x.t1, x.a_secs, x.b_secs, x.outcome], [239, 248, 5, 2, 'answered']);
    assert.deepStrictEqual([x.hp0, x.hp1, x.ohp0, x.ohp1], [81, 2, 73, 42]);
});

test('exchange: not answered', () => {
    // sand_king (pid 9) targets luna (h0) at 246, 247 and 248; luna targets only bounty_hunter (h7) in that time
    const x = rowsOf(A1, { kind: 'exchange', hero: 'sand_king', from: '4:05', to: '4:10' }).find(r => r.hero === 'sand_king' && r.other === 'luna');
    assert.deepStrictEqual([x.t, x.t1, x.a_secs, x.b_secs, x.outcome], [246, 248, 3, 0, 'none_back']);
});

test('exchange: attack seconds 6 apart are two exchanges, neither answered', () => {
    // bounty_hunter (pid 7) targets jakiro (h3) at 521.13; jakiro targets bounty_hunter (h7) at 526.97 (second 527); nothing else between the two
    const x = rowsOf(A1, { kind: 'exchange', hero: 'jakiro', from: '8:35', to: '8:50' })
        .filter(r => ['jakiro', 'bounty_hunter'].includes(r.hero) && ['jakiro', 'bounty_hunter'].includes(r.other) && r.t < 530);
    assert.deepStrictEqual(x.map(r => [r.hero, r.t, r.t1, r.a_secs, r.b_secs, r.outcome]),
        [['bounty_hunter', 521, 521, 1, 0, 'none_back'], ['jakiro', 527, 527, 1, 0, 'none_back']]);
});

// ---- kill_try ---------------------------------------------------------------------------------------------------------------

test('kill_try: a try that killed, by two heroes, the first attacker named', () => {
    // jakiro (pid 3) hp 72, 53, 42, 32, 21, 19, 5 at 238-244 and no snapshot after; bounty_hunter and sand_king both target it (h3) from 238 (sand_king also at 243, 244)
    const k = rowsOf(A1, { kind: 'kill_try', hero: 'jakiro', from: '3:55', to: '4:05' }).find(r => r.other === 'jakiro');
    assert.deepStrictEqual([k.hero, k.t, k.t1, k.hpmin, k.outcome], ['bounty_hunter', 238, 244, 5, 'killed']);
    assert.deepStrictEqual([...new Set(k.who.split(',').filter(Boolean))].sort(), ['bounty_hunter', 'jakiro', 'sand_king']);
});

test('kill_try: a try on a hero at 24% that lived', () => {
    // zuus (pid 8) targets sniper (h2) at 247, 249, 250, 252, 253; sniper hp 66, 59, 57, 50, 35, 25, 24 over 247-253, then 13 at 254 and alive to the end of the cut
    const k = rowsOf(A1, { kind: 'kill_try', hero: 'sniper', from: '4:05', to: '4:15' }).find(r => r.other === 'sniper');
    assert.deepStrictEqual([k.hero, k.t, k.t1, k.hpmin, k.outcome], ['zuus', 247, 253, 24, 'lived']);
});

test('kill_try: burst from above the 40% bar counts when the target is dead within 5 s', () => {
    // witch_doctor (pid 2) targeted at 275 (lich, h2) and 277 (bristleback), hp 65, 58, 58 at 275-277 (all above 40), 43 at 278, last snapshot 280.70 at hp 44, then none until respawn
    const k = rowsOf('h2hlift1_B_off-rad_10', { kind: 'kill_try', hero: 'witch_doctor', from: '4:30', to: '4:40' }).find(r => r.other === 'witch_doctor');
    assert.deepStrictEqual([k.hero, k.t, k.t1, k.hpmin, k.outcome], ['lich', 275, 277, 58, 'killed']);
    assert.strictEqual(k.side, 'opp');
});

// ---- visit ------------------------------------------------------------------------------------------------------------------

test('visit: ended by death', () => {
    // jakiro (pid 3) in the bot lane (nearest polyline within 1100) from 11 s to its last snapshot at 244, with the lane left only for the base before 11; dead after 244.17
    const v = rowsOf(A1, { kind: 'visit', hero: 'jakiro', from: '0:05', to: '4:10' }).find(r => r.hero === 'jakiro' && r.t === 11);
    assert.deepStrictEqual([v.lane, v.t, v.t1, v.outcome], ['bot', 11, 244, 'dead']);
});

test('visit: steps out of up to 5 s stay in the visit, 8 s end it', () => {
    // zuus (pid 8) in the mid lane from 4 s; out of it 134-138 (5 s) and back at 139 (same visit); out 236-243 (8 s), back at 244 (the next visit); its mode at 235 is rune
    const v = rowsOf(A1, { kind: 'visit', hero: 'zuus', from: '0:00', to: '4:10' }).filter(r => r.hero === 'zuus' && r.t >= 0);
    assert.deepStrictEqual([v[0].lane, v[0].t, v[0].t1, v[0].outcome], ['mid', 4, 235, 'rune']);
    assert.strictEqual(v[1].t, 244);
});

test('visit: a stock visit ends in the mode the hero was in', () => {
    // pudge (pid 1) in the mid lane from 543 to 551 (attack on h6 at 545-547 and 549); mode attack at 551 (snapshot 550.90); 552 onward it is out of the lane for 7 s
    const v = rowsOf(STOCK, { kind: 'visit', hero: 'pudge', from: '9:00', to: '9:15' }).find(r => r.hero === 'pudge');
    assert.deepStrictEqual([v.lane, v.t, v.t1, v.outcome], ['mid', 543, 551, 'attack']);
});

// ---- job --------------------------------------------------------------------------------------------------------------------

test('job: a stack aborted for a mode change ends with that reason', () => {
    // earthshaker (pid 4): lane_job_start kind=stack at 165.300, lane_job_abort reason=mode-end at 171.567
    const j = rowsOf(A1, { kind: 'job', hero: 'earthshaker', from: '2:40', to: '2:55' }).find(r => r.hero === 'earthshaker');
    assert.deepStrictEqual([j.t, j.t1, j.outcome], [165.3, 171.6, 'mode-end']);
});

test('job: a pull ends at its graded lane_job line, with the grade as the reason', () => {
    // jakiro (pid 3): lane_job_start kind=full at 157.433, nothing ended until ev=lane_job grade=mistake:weak-pull at 178.800 (lane_job_hold lines between are no end)
    const j = rowsOf(A1, { kind: 'job', hero: 'jakiro', from: '2:30', to: '3:00' }).find(r => r.hero === 'jakiro');
    assert.deepStrictEqual([j.t, j.t1, j.outcome], [157.4, 178.8, 'mistake:weak-pull']);
});

test('job: a trip with no end logged before the log ends has no end', () => {
    // luna (pid 0): farm_trip_start 694.900, farm_trip_end why=back 714.600, farm_trip_start 714.867 and no farm_trip_end after (the log ends at 723.97)
    const j = rowsOf('h2hlift1_A_off-dir_3', { kind: 'job', hero: 'luna' }).filter(r => r.hero === 'luna');
    assert.deepStrictEqual(j.map(r => [r.t, r.t1, r.outcome]), [[694.9, 714.6, 'back'], [714.9, null, 'no_end']]);
});
