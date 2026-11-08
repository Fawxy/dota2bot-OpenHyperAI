'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'lever_effect.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-le-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const wave = (t, team, lane, m45) => line(t, `lane_ctl team=${team} lane=${lane} kind=wave wave=${t - 2} own=0 m45=${m45}`);
const chk = (t, team, lane, own) => line(t, `lane_ctl team=${team} lane=${lane} kind=chk wave=${t - 47} own=${own}`);
const swing = (t, pid, kind, result = 'ok') => line(t, `idle_swing pid=${pid} kind=${kind} mode=safe result=${result} reason=ok ranged=0 walk=0 hp=100 hf=0.2`);

test('lever effect: waves bucketed by the lane\'s own and enemy idle swings in the 45 s, effect = own45 - m45', () => {
    const out = run([
        // Radiant pos1 lanes bot (3); Dire pos3 lanes bot (3) too; Dire pos1 lanes top (1).
        line(0, 'bot pid=0 hero=h0 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=3 pos=3'),
        line(0, 'bot pid=6 hero=h6 team=3 pos=1'),
        // Wave 60, Radiant bot: two shove swings of ours inside the window, effect +900.
        wave(62, 2, 3, 1000), chk(107, 2, 3, 1900),
        swing(70, 0, 'shove'), swing(80, 0, 'shove'),
        // A failed swing and one after the check do not count.
        swing(75, 0, 'predeny', 'skip'), swing(110, 0, 'predeny'),
        // Same wave from Dire's side of bot: the shoves are theirs; Dire's own predeny at 90. Effect -700.
        wave(62, 3, 3, 0), chk(107, 3, 3, -700),
        swing(90, 5, 'predeny'),
        // Dire top, same wave: nobody swung there (pid 6 swung only outside the window): the control, effect +100.
        wave(62, 3, 1, 200), chk(107, 3, 1, 300),
        swing(200, 6, 'setup'),
        // Wave 90 Dire top, control again, effect -100.
        wave(92, 3, 1, 200), chk(137, 3, 1, 100),
        // A wave with no check is dropped.
        wave(122, 2, 3, 500),
    ]);
    const row = (ours, theirs) => out.find(r => r.ours === ours && r.theirs === theirs);
    assert.deepStrictEqual([row('shove', 'predeny').n, row('shove', 'predeny').mean, row('shove', 'predeny').swings], [1, 900, 2]);
    assert.deepStrictEqual([row('predeny', 'shove').n, row('predeny', 'shove').mean], [1, -700]);
    assert.deepStrictEqual([row('-', '-').n, row('-', '-').mean, row('-', '-').sd], [2, 0, 100]);
    assert.strictEqual(out.length, 3);
});
