'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const read = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', name), 'utf8');

function run(name, lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pc-')), 'a.log');
    const at = (l) => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(read(name), params);
    s.db.close();
    return out;
}

const pc = (t, f) => line(t, `pull_clear pid=5 pos=5 lane=3 camp=1 ${f}`);

test('per decision: a started farm with its end, own neutral kills, gold above passive and a death; a skip with its gate', () => {
    const out = run('pull_clear.sql', [
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        // Farm 1: starts 0.1 s after the pull, two neutrals, both killed by pid 5 (a third by an ally), +60 gold in 20 s (30 above passive).
        pc(100, 'phase=start ago=0.1 div=0.75 n0=2 hp0=0.9'),
        line(104, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=5 camp=1 np=5 nd=100'),
        line(108, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=5 camp=1 np=5 nd=100'),
        line(109, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=1 camp=1 np=1 nd=100'),
        pc(120, 'phase=end ago=0.1 div=0.75 n0=2 res=ok why=back nl=0 back=119 g0=500 g1=560 secs=20 hp0=0.9 hp=0.7 died=0'),
        // Farm 2: given up to a core mid-clear; a neutral death after its end is not the farm's.
        pc(200, 'phase=start ago=0.2 div=1 n0=3 hp0=1'),
        pc(206, 'phase=end ago=0.2 div=1 n0=3 res=fail why=interrupted:yield nl=3 g0=600 g1=600 secs=6 hp0=1 hp=1 died=0'),
        line(210, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=5 camp=1 np=5 nd=100'),
        // Skip: a core's trip was already on the camp.
        pc(300, 'phase=skip ago=0.1 div=0.5 n0=2 why=core-coming'),
    ]);
    assert.deepStrictEqual(out.map((r) => [r.t, r.phase, r.why, r.n0, r.nl, r.gain, r.nk, r.died]), [
        [100, 'start', 'back', 2, 0, 30, 2, 0],
        [200, 'start', 'interrupted:yield', 3, 3, -9, 0, 0],
        [300, 'skip', 'core-coming', 2, null, null, 0, null],
    ]);
});
