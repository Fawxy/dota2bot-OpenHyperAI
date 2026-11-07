'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const q = name => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-drillpull-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(q('drill_pull'), params);
    s.db.close();
    return out;
}

const role = (pid, team, r, name = 'pull') => line(0.5, `drill ph=role name=${name} pid=${pid} team=${team} pos=5 role=${r}`);
const wave = (t, w, m45, pe) => line(t, `lane_ctl team=2 lane=3 kind=wave wave=${w} own=1000 m45=${m45}${pe !== undefined ? ` pe=${pe}` : ''}`);
const chk = (t, w, own) => line(t, `lane_ctl team=2 lane=3 kind=chk wave=${w} own=${own}`);

test('drill_pull: one row per drill-decided slot, joined to its pull result and the wave decision and check', () => {
    const out = run([
        role(3, 2, 'cast'), role(4, 2, 'bench'),
        // Input on: pulled ok; the controller predicted -300, the lane moved -400 against the plain forecast.
        wave(62, 60, 1500, -300), chk(107, 60, 1100),
        line(66, 'choice kind=pull pid=3 go=1 want=1 lane=3 slot=77.2 rule=drill src=own'),
        line(100, 'pull_job pid=3 camp=1 slot=77.2 res=ok why=ok div=1 pos=5 lane=3'),
        // Control rep: stayed, why=drill; no pull line.
        wave(92, 90, 1200, -250), chk(137, 90, 1300),
        line(96, 'choice kind=pull pid=3 go=0 want=0 lane=3 slot=107.1 why=drill src=own'),
        // Input on, cancelled: e_ctl stays the plain error.
        wave(122, 120, 1400, -200), chk(167, 120, 1350),
        line(126, 'choice kind=pull pid=3 go=1 want=1 lane=3 slot=137.4 rule=drill src=own'),
        line(140, 'pull_job pid=3 camp=1 slot=137.3 res=fail why=cancelled:one div=0 pos=5 lane=3'),
        // A pull choice outside the drill's rule is not a drill row.
        line(150, 'choice kind=pull pid=3 go=0 want=0 lane=3 slot=167 why=lane src=own'),
    ]);
    assert.strictEqual(out.length, 3);
    assert.deepStrictEqual(out.map(r => [r.wave, r.input, r.go, r.res]), [[60, 'on', 1, 'ok'], [90, 'off', 0, null], [120, 'on', 1, 'fail']]);
    assert.deepStrictEqual([out[0].effect, out[0].e_plain, out[0].e_ctl], [-400, 400, 100]);
    assert.deepStrictEqual([out[1].effect, out[1].e_ctl, out[1].why], [100, 100, 'drill']);
    assert.deepStrictEqual([out[2].why_end, out[2].e_ctl], ['cancelled:one', 50]);
});

test('drill_pull: games that are not pull drills give no rows', () => {
    const out = run([
        role(0, 2, 'cast', 'lane-spot'),
        line(66, 'choice kind=pull pid=0 go=1 want=1 lane=3 slot=77.2 rule=drill src=own'),
    ]);
    assert.strictEqual(out.length, 0);
});
