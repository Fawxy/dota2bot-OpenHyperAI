'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const near = 'p1d=100 p1r=150 p1t=0';

function rows(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-idle-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'lasthit_idle_lf.sql'), 'utf8'), { file: f, game: 1, until: 600 });
    s.db.close();
    return out;
}

test('idle-in-range deaths carry the mode and the lf of the snap just before them; own, attacked, far and late deaths do not', () => {
    const out = rows([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(99, 'snap pid=1 x=0 y=0 alive=1 mode=laning lf="ph=lasthit sc=1.2 aw=100 pk=1.2 n=1 sk=0 ch=1"'),
        line(100, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        // Its own last hit, an attacked creep, a creep beyond range + 300, one after `until`: none is idle.
        line(110, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=1 ${near}`),
        line(120, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none p1d=100 p1r=150 p1t=0.2 p1a=0.2`),
        line(130, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none p1d=600 p1r=150 p1t=0`),
        line(605, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        // The last snap is 3 s old: the mode still reads, lf does not.
        line(200, 'snap pid=1 x=0 y=0 alive=1 mode=farm lf="ph=hold sc=0.1 aw=10 pk=5.0 n=0 sk=0 ch=0"'),
        line(203, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
    ]);
    assert.deepStrictEqual(out.map(r => [r.t, r.mode, r.lf]), [
        [100, 'laning', 'ph=lasthit sc=1.2 aw=100 pk=1.2 n=1 sk=0 ch=1'],
        [203, 'farm', null],
    ]);
});
