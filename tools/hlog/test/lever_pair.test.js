'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lever_pair.sql'), 'utf8');

function run(games, params) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-lp-'));
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    const s = new Store(':memory:');
    for (const [name, lines] of Object.entries(games)) {
        const f = path.join(dir, `${name}.log`);
        fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
        s.ingest(f);
    }
    s.refreshViews();
    const out = s.query(sql, params);
    s.db.close();
    return out;
}

const wave = (w, team, lane, m45) => line(w + 2, `lane_ctl team=${team} lane=${lane} kind=wave wave=${w} own=0 m45=${m45}`);
const chk = (w, team, lane, own) => line(w + 47, `lane_ctl team=${team} lane=${lane} kind=chk wave=${w} own=${own}`);
const swing = (t, pid) => line(t, `idle_swing pid=${pid} kind=setup mode=safe result=ok reason=ok ranged=0 walk=0 hp=100 hf=0.2`);
const bots = [line(0, 'bot pid=0 hero=h0 team=2 pos=1'), line(0, 'bot pid=5 hero=h5 team=3 pos=1')];

test('lever pair: the same wave of the input and control games, diff = on_eff - off_eff on Radiant bot', () => {
    const games = {
        on: [...bots,
            wave(60, 2, 3, 1000), chk(60, 2, 3, 1800), swing(70, 0), swing(80, 0), swing(75, 5),
            wave(90, 2, 3, 500), chk(90, 2, 3, 900),
            // Another lane, and a wave the control never checked: neither pairs.
            wave(60, 2, 1, 0), chk(60, 2, 1, 999), wave(120, 2, 3, 0), chk(120, 2, 3, 100)],
        off: [...bots,
            wave(60, 2, 3, 1200), chk(60, 2, 3, 1400),
            wave(90, 2, 3, 400), chk(90, 2, 3, 600),
            wave(120, 2, 3, 0)],
    };
    const rows = run(games, { on: '%on.log', off: '%off.log' });
    assert.deepStrictEqual(rows.map(r => [r.wave, r.on_eff, r.off_eff, r.diff, r.on_sw, r.off_sw]),
        [[60, 800, 200, 600, 2, 0], [90, 400, 200, 200, 0, 0]]);
    const [s] = run(games, { on: '%on.log', off: '%off.log', sum: 1 });
    // diffs 600 and 200: mean 400, sample sd 283, se 200.
    assert.deepStrictEqual([s.n, s.mean, s.se, s.on_sw], [2, 400, 200, 1]);
});
