'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'idle_swings.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-is-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return Object.fromEntries(out.map(r => [r.kind, r]));
}

const sw = (pid, n, x, extra = '') => `idle_swing pid=${pid} kind=predeny mode=safe n=${n} cx=${x} cy=0 result=ok reason=ok ranged=0 walk=0 hp=100 hf=0.2${extra}`;

test('predeny: one creep per start, its fate from the own creep death after the last swing near its place', () => {
    const out = run([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        // Creep A: pid 1 swings twice (n 0, 1), our pid 5 denies it 2 s after the last swing: denied, not by_me.
        line(100, sw(1, 0, 1000)),
        line(101.5, sw(1, 1, 1050)),
        line(103.5, 'own_creep_death team=2 kind=melee x=1060 y=0 hp=0.05 by=5'),
        // Creep B: pid 1 starts again and denies it itself with the swing (dn): denied, by_me, self.
        line(110, sw(1, 0, 2000, ' dn=1')),
        line(110.5, 'own_creep_death team=2 kind=melee x=2000 y=0 hp=0.05 by=1'),
        // Creep C: pid 5 (focus, an ally on it); it dies with no denier: lost. A death 900 away right after is not it.
        line(120, sw(5, 0, 3000, ' focus=1')),
        line(121, 'own_creep_death team=2 kind=melee x=3900 y=0 hp=0.05 by=1'),
        line(122, 'own_creep_death team=2 kind=melee x=3050 y=0 hp=0.05 by=none'),
        // Creep D: pid 5, no death within 8 s: unmatched. A failed swing counts as a swing, not a creep.
        line(130, sw(5, 0, 4000)),
        line(131, 'idle_swing pid=5 kind=predeny mode=safe n=1 cx=4000 cy=0 result=fail reason=missed ranged=0 walk=0 hp=90 hf=0.2'),
        line(140, 'own_creep_death team=2 kind=melee x=4000 y=0 hp=0.05 by=5'),
        // A ranged death at creep B's place does not match a melee creep.
        // Shove swings.
        line(150, 'idle_swing pid=1 kind=shove mode=shove cx=0 cy=0 result=ok reason=ok ranged=0 walk=0 hp=300 hf=0.5'),
        line(152, 'idle_swing pid=1 kind=shove mode=shove cx=0 cy=0 result=ok reason=ok ranged=0 walk=0 hp=50 hf=0.1 lh=1'),
    ]);
    const p = out.predeny;
    assert.deepStrictEqual([p.swings, p.ok, p.fail, p.creeps, p.denied, p.by_me, p.lost, p.unmatched, p.rate, p.self, p.focus],
        [6, 5, 1, 4, 2, 1, 1, 1, 0.5, 1, 1]);
    assert.deepStrictEqual([out.shove.swings, out.shove.ok, out.shove.fail], [2, 2, 0]);
});
