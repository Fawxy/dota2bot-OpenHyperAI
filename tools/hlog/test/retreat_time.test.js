'use strict';
// retreat_time and retreat_tails (slice retreat-gone): retreat seconds split by an enemy hero in reach and by which of our
// episodes held them; each episode's tail after the last enemy in reach.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const query = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');
const PX = -2000, PY = 3000;

const bots = heroes => heroes.map(([pid, team, pos]) => line(0, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos} ours=Retreat:${team === 2 ? 1 : 0}`));
const snap = (t, pid, x, y, o = {}) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${o.hp ?? 100} mode=${o.mode ?? 'laning'} ` +
    `lvl=3 deaths=0 ar=${o.ar ?? 550} ld=0 hit=0`);
const start = (t, pid, ep, why) => line(t, `retreat ph=start pid=${pid} kind=ours ep=${ep} why=${why} hp=0.9 thr=0.6 band=pressured reach=1 burst=0.2 tower=0 budget=0.5 purp=free anchor=tower cost=1 alt=2 dist=2000`);
const end = (t, pid, ep, res) => line(t, `retreat ph=end pid=${pid} kind=ours ep=${ep} why=threat anchor=tower res=${res} secs=1 hpl=0 twr=0 wave=0 dmgh=0`);

function run(name, lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rtime-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(query(name), params);
    s.db.close();
    return out;
}

// Ours (pid 1, Radiant): a threat episode 100-110, the chaser (ar 150, so reach 750) at 500 until 103, then 3,000 off: 4 s in
// reach, 7 s run-on at full HP. A heal episode 200-205 with nobody near: 6 s, none in reach. OHA's pid 6 retreats 300-302
// with ours far: its 3 s count on its side, in no episode of ours.
function game() {
    const lines = bots([[1, 2, 1], [6, 3, 1]]);
    lines.push(start(100, 1, 1, 'threat'), end(110, 1, 1, 'safe'), start(200, 1, 2, 'heal'), end(205, 1, 2, 'anchor'));
    for (let t = 95; t <= 320; t++) {
        const mode1 = (t >= 100 && t <= 110) || (t >= 200 && t <= 205) ? 'retreat' : 'laning';
        lines.push(snap(t, 1, PX, PY, { mode: mode1, hp: t >= 200 && t <= 205 ? 25 : 100 }));
        lines.push(snap(t, 6, t <= 103 ? PX + 500 : PX + 3000, PY, { ar: 150, mode: t >= 300 && t <= 302 ? 'retreat' : 'laning' }));
    }
    return lines;
}

test('retreat_time: seconds split by an enemy in reach, and the no-reach ones by our heal episode or any other', () => {
    const by = Object.fromEntries(run('retreat_time', game(), { until: 600 }).map(r => [r.side, r]));
    assert.deepStrictEqual([by.ours.secs, by.ours.reach, by.ours.noreach, by.ours.nr_ep, by.ours.nr_heal, by.ours.nr_high], [17, 4, 13, 7, 6, 7]);
    assert.deepStrictEqual([by.oha.secs, by.oha.reach, by.oha.nr_ep], [3, 0, 0]);
});

test('retreat_tails: the tail runs from the last second in reach, or the whole episode when nobody came', () => {
    const out = run('retreat_tails', game()).map(r => [r.t, r.why, r.tail, r.reached]);
    assert.deepStrictEqual(out, [[100, 'threat', 7, 1], [200, 'heal', 5, 0]]);
});
