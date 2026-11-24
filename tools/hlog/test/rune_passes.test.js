'use strict';
// The rune pass reader (queries/rune_passes.sql): a hero of the owning side out of its lane within :r of its jungle's live bounty,
// and whether it took it. Radiant luna (pid 0, pos 1: the bot lane) and lich (pid 1, pos 5); Dire bane (pid 5, pos 5), synthetic.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const RAD = [595, -4660];   // rune 3, Radiant's jungle bounty
const DIRE = [-997, 4431];  // rune 2, Dire's
const BOT_LANE = [3000, -6200];
const IN_BOT = [595, -6000];  // in the bot lane, 1,340 from rune 3
const FOUNTAIN = [-6700, -6700];
const DIRE_FOUNTAIN = [6928, 6372];
const at = (p, dy) => [p[0], p[1] + dy];

/**
 * 4:00 spawn, Radiant's (rune 3): luna leaves the bot lane and passes at 1,460 from 300 to 309 (came bot, untaken);
 *      lich walks from the fountain to 660 off at 330 and onto the spot at 340, taking it at 341.5 (came base, taken).
 *      bane (Dire) stands 660 off from 250 to 260: not its side's rune, no pass.
 * 4:00 spawn, Dire's (rune 2): bane passes from 270 (came from the Radiant jungle: other) and takes it at 274.5.
 * 8:00 spawn, Radiant's: luna stands in the bot lane 1,340 off from 480 to 600 (its own lane: no pass); lich 660 off from 500 to
 *      512, dead 506 to 509, so two passes, neither taken; Radiant's stays untaken (gone 720).
 */
function gameLines() {
    const out = [
        line(-90, 'bot pid=0 hero=luna team=2 pos=1'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=bane team=3 pos=5'),
        line(341.5, `rune_pickup pid=1 team=2 rune=3 kind=bounty x=${RAD[0]} y=${RAD[1]}`),
        line(274.5, `rune_pickup pid=5 team=3 rune=2 kind=bounty x=${DIRE[0]} y=${DIRE[1]}`),
    ];
    const snap = (t, pid, p, alive = 1) => line(t, `snap pid=${pid} x=${p[0]} y=${p[1]} alive=${alive} hp=${alive ? 80 : 0} mode=laning`);
    for (let t = 200; t <= 620; t++) {
        let l = BOT_LANE;
        if (t >= 300 && t < 310) l = at(RAD, 1460);
        if (t >= 480) l = IN_BOT;
        out.push(snap(t, 0, l));
        let c = FOUNTAIN, alive = 1;
        if (t >= 330 && t < 340) c = at(RAD, 660);
        if (t >= 340 && t < 350) c = RAD;
        if (t >= 350 && t < 500) c = BOT_LANE;
        if (t >= 500 && t <= 512) { c = at(RAD, 660); alive = t >= 506 && t <= 509 ? 0 : 1; }
        if (t > 512) c = BOT_LANE;
        out.push(snap(t, 1, c, alive));
        let b = DIRE_FOUNTAIN;
        if (t >= 250 && t <= 260) b = at(RAD, 660);
        if (t >= 270 && t <= 275) b = at(DIRE, 300);
        out.push(snap(t, 5, b));
    }
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

test('rune_passes: own-side heroes out of their lane near a live own bounty, split by own-lane or dead seconds, taken or not', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rune-pass-'));
    const file = path.join(dir, '2026-11-24T00-00-00-rp_A_off_1.log');
    fs.writeFileSync(file, gameLines().join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'rune_passes.sql'), 'utf8');
    const rows = store.query(sql, { like: '%rp_A_off_1%', until: 600 }).map(r => ({ ...r }));
    const got = rows.map(r => [r.sp, r.rune, r.pid, r.t0, r.t1, r.dmin, r.tmin, r.came, r.taken, r.gone]);
    assert.deepStrictEqual(got, [
        [240, 2, 5, 270, 274, 300, 270, 'other', 1, 274.5],
        [240, 3, 0, 300, 309, 1460, 300, 'bot', 0, 341.5],
        [240, 3, 1, 330, 341, 0, 340, 'base', 1, 341.5],
        [480, 3, 1, 500, 505, 660, 500, 'bot', 0, 720],
        [480, 3, 1, 510, 512, 660, 510, 'bot', 0, 720],
    ]);
});
