'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const snap = (t, pid, deaths) => line(t, `snap pid=${pid} x=0 y=0 alive=1 hp=50 deaths=${deaths} mode=attack d=0.75 by="attack 0.75 by raw"`);
const trade = (t, o) => line(t, `trade pid=1 role=core lf=${o.lf ?? 1} kind=${o.kind ?? 'kill'} tgt=6 result=${o.result} why=${o.why ?? 'target_dead'}`
    + ` dur=${o.dur ?? 0} hpd=0 thpd=0 hp=0.8 thp=0.3 en=1 al=1 cr=0 mode=2 md=0.75`);

test('lane commits: taken, kills and lost per game and role; a death inside a taken commit counts, one long after does not', () => {
    const lines = [line(0, 'bot pid=1 hero=h1 team=2 pos=1'), line(0, 'bot pid=6 hero=h6 team=3 pos=3')];
    for (let t = 90; t <= 140; t++) lines.push(snap(t, 1, 0));
    lines.push(trade(100, { result: 'kill', dur: 2 }));
    // A taken commit from 140 ends at 141 (target lost) and the core dies at 141 (no snapshot until its respawn at 170).
    lines.push(trade(141, { result: 'done', why: 'target_lost', dur: 1 }));
    lines.push(snap(170, 1, 1));
    for (let t = 171; t <= 260; t++) lines.push(snap(t, 1, 1));
    lines.push(trade(200, { result: 'lost', why: 'not_taken' }));
    // A trade, and a commit outside lane fights (lf=0): neither is read by the default lf=1.
    lines.push(trade(210, { kind: 'trade', result: 'done' }), trade(220, { result: 'kill', lf: 0, dur: 1 }));
    // A commit taken at 250 with the core dying at 261 (11 s after its line): not the commit's death.
    lines.push(trade(250, { result: 'done', dur: 2 }));
    lines.push(snap(261, 1, 1), snap(290, 1, 2));
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lfc-')), 'a.log');
    // The store reads a clock going back as a new game, so the lines go out in time order.
    const at = l => Number(l.match(/t=([\d.]+)/)[1]);
    fs.writeFileSync(f, lines.sort((a, b) => at(a) - at(b)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lane_commits.sql'), 'utf8');
    const rows = p => s.query(sql, p).map(r => [r.role, r.offers, r.taken, r.kills, r.lost, r.deaths]);
    assert.deepStrictEqual(rows({}), [['core', 4, 3, 1, 1, 1]]);
    assert.deepStrictEqual(rows({ lf: 0 }), [['core', 1, 1, 1, 0, 0]]);
    s.db.close();
});
