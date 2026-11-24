'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pull_rig.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pr-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, { like: null, team: null, to: null, ...params });
    s.db.close();
    return out;
}

let cid = 0;
const wcd = (t, x, y, by, born, lane = 'bot') =>
    line(t, `wave_creep_death team=2 kind=melee x=${x} y=${y} hp=0.05 by=${by} cid=${++cid} lane=${lane} born=${born}`);

test('a pulled wave against an unpulled one: the job names its wave by slot and lane number, its creeps by where they died', () => {
    const out = run([
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=8 hero=h8 team=3 pos=5'),
        // slot 77 pulls the wave born at 1:00 (floor(76 / 30) = 2) on lane 3, the wave line's `bot`; the stay ended done.
        line(100, 'pull_job pid=5 pos=5 lane=3 camp=8 slot=77 res=ok why=ok st=done'),
        // at the bot pull camp (camp 8, -721, -7696): two to the neutrals, one our puller denied; one walked back to lane.
        wcd(95, -700, -7650, 'none', 60.1), wcd(97, -760, -7700, 'none', 60.1), wcd(99, -700, -7700, 5, 60.1),
        wcd(130, 0, -6000, 'none', 60.1),
        // the :30 wave, never pulled, dies in lane; Dire's pull of the same slot is the other team's.
        wcd(120, 300, -6000, 'none', 90.2), wcd(121, 320, -6000, 'none', 90.2),
        line(100, 'pull_job pid=8 pos=5 lane=3 camp=2 slot=107 res=ok why=ok'),
    ]);
    assert.deepStrictEqual(out.map(r => [r.lane, r.born, r.pulled, r.st, r.n, r.at_camp, r.denied]),
        [['bot', 60, 1, 'done', 4, 3, 1], ['bot', 90, 0, null, 2, 0, 0]]);
});
