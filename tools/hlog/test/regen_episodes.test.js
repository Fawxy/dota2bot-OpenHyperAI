'use strict';
// The regen episode reader (queries/regen_episodes.sql): a hero of ours under half HP in its own lane, and how the episode ended.
// Radiant luna (pid 0, pos 1: the bot lane) and lich (pid 1, pos 5: the bot lane too) on a synthetic game.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const BOT_LANE = [3000, -6200];
const TOP_LANE = [-6200, 3000];
const FOUNTAIN = [-6700, -6700];

/**
 * luna: under half at 100 (holding 2 tangos and a salve), a tango starts at 103, back over half in lane at 110 (`lane`, used);
 *       a hero hit it at 100 and 101, so the gate (600 missing of 1,000 fits a tango) first holds at 104, after the use;
 *       under half again at 150 holding a salve, walks to the fountain from 160 (`fountain`, unused), back in lane at 200;
 *       550 missing fits the salve's 390 and nothing hit it, so the gate holds from 150, a missed opportunity.
 * lich: under half in the top lane at 120 (not its lane: no episode), under half in its lane at 130 holding nothing, killed at
 *       140 (no snapshots 141-159, its deaths counter risen at 160 at the fountain; `death`).
 */
function gameLines() {
    const out = [
        line(-90, 'bot pid=0 hero=luna team=2 pos=1'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'inv pid=0 items="s0=tango:2 s1=flask:1 s15=tpscroll:1"'),
        line(-90, 'inv pid=1 items="s0=ward_observer:1 s9=tango:3"'),
        line(103, 'regen_obs pid=0 item=tango state=start by=oha'),
        line(102, 'regen_win pid=0 mode=1 len=2 miss0=300 missmax=300 tg=2 sv=1 tge=112 sve=390 tree=200 under=0 used=tango'),
        line(152, 'regen_win pid=0 mode=1 len=5 miss0=300 missmax=300 tg=0 sv=1 tge=0 sve=390 tree=-1 under=1 used=-'),
        line(120, 'inv pid=0 items="s1=flask:1 s15=tpscroll:1"'),
    ];
    const snap = (t, pid, p, hp, deaths = 0, hit = 0) =>
        line(t, `snap pid=${pid} x=${p[0]} y=${p[1]} alive=1 hp=${hp} deaths=${deaths} mode=laning hpm=1000 hit=${hit}`);
    for (let t = 0; t <= 240; t++) {
        let p = BOT_LANE, hp = 80;
        if (t >= 100 && t < 110) hp = 40;
        if (t >= 150 && t < 160) hp = 45;
        if (t >= 160 && t < 200) { p = FOUNTAIN; hp = 45; }
        out.push(snap(t, 0, p, hp, 0, t === 100 || t === 101 ? 1 : 0));
        if (t > 140 && t < 160) continue;
        let q = [BOT_LANE[0] + 100, BOT_LANE[1]], lhp = 90;
        if (t >= 118 && t < 125) { q = TOP_LANE; lhp = 30; }
        if (t >= 130 && t <= 140) lhp = t === 140 ? 0 : 35;
        if (t >= 160) { q = t < 175 ? FOUNTAIN : [BOT_LANE[0] + 100, BOT_LANE[1]]; lhp = 100; }
        out.push(snap(t, 1, q, lhp, t >= 160 ? 1 : 0));
    }
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

test('regen_episodes: own-lane onsets under half, ended by lane, fountain or death, with what was held and used', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-regen-ep-'));
    const file = path.join(dir, '2026-11-24T00-00-00-re_A_off_1.log');
    fs.writeFileSync(file, gameLines().join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'regen_episodes.sql'), 'utf8');
    const rows = store.query(sql, { like: '%re_A_off_1%', until: 600 }).map(r => ({ ...r }));
    const got = rows.map(r => [r.pid, r.t0, r.t1, r.res, r.tg, r.sv, r.used, r.unused, r.off_s, r.win, r.win_used, r.use_t, r.gate]);
    assert.deepStrictEqual(got, [
        [0, 100, 110, 'lane', 2, 1, 'tango', 0, 0, 1, 1, 103, 104],
        [1, 130, 140, 'death', 0, 0, '-', 0, 35, 0, 0, null, null],
        [0, 150, 160, 'fountain', 0, 1, '-', 1, 40, 0, 0, null, 150],
    ]);
});
