'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'retreat_episodes.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-re-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

const start = (pid, ep, extra = '') => `retreat ph=start pid=${pid} kind=ours ep=${ep} why=threat hp=0.9 thr=0.62 band=pressured reach=2 burst=0.2 tower=0 budget=0.5 purp=free anchor=tower cost=1 alt=3 dist=2400${extra}`;
const end = (pid, ep, res, extra = '') => `retreat ph=end pid=${pid} kind=ours ep=${ep} why=threat anchor=tower res=${res} secs=4 hpl=0.1 twr=0 wave=1 dmgh=0.05${extra}`;

test('episodes: start joined to its own end by ep; a restart within 3 s is a swap; plain walks and late starts are not rows', () => {
    const out = run([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=2 hero=h2 team=2 pos=5'),
        // pid 1: ep 1 ends safe at 104; ep 2 starts 2 s later (a swap) and ends anchor; ep 3 starts 10 s after that.
        line(100, start(1, 1)),
        line(104, end(1, 1, 'safe')),
        line(106, start(1, 2)),
        line(110, end(1, 2, 'anchor')),
        line(120, start(1, 3, ' hp=0.5')),
        line(125, end(1, 3, 'died')),
        // pid 2's episode numbers interleave: ep 4 must not take pid 1's lines.
        line(105, start(2, 4)),
        line(108, end(2, 4, 'safe')),
        // A plain walk and an episode after the cap are no rows.
        line(130, 'retreat ph=start pid=2 kind=plain anchor=fountain hp=0.4 x=0 y=0'),
        line(700, start(1, 5)),
    ]);
    assert.strictEqual(out.length, 4);
    const by = Object.fromEntries(out.map(r => [`${r.pid}:${r.t}`, r]));
    assert.deepStrictEqual([by['1:100'].res, by['1:100'].back3, by['1:100'].full, by['1:100'].pos], ['safe', 1, 1, 1]);
    assert.deepStrictEqual([by['1:106'].res, by['1:106'].back3], ['anchor', 0]);
    assert.deepStrictEqual([by['1:120'].res, by['1:120'].full], ['died', 0]);
    assert.deepStrictEqual([by['2:105'].res, by['2:105'].pos, by['2:105'].wave], ['safe', 5, 1]);
});
