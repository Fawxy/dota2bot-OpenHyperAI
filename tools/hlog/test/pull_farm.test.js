'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pull_farm.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pf-')), 'a.log');
    // The parser starts a new game when time goes back, so the cases below are written in any order and sorted here.
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

// Camp 13's spawn is (-2415, -8402). Team 2 pulls it at slot 170; pid 3 is their other support, pid 6 the other team's core.
const base = [
    line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
    line(0, 'bot pid=3 hero=h3 team=2 pos=4'),
    line(0, 'bot pid=6 hero=h6 team=3 pos=1'),
    line(0, 'bot pid=9 hero=h9 team=3 pos=5'),
    line(165, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=170 res=ok why=ok'),
    // a failed pull has no row.
    line(230, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=231 res=fail why=cancelled:empty'),
];

test('per ok pull: the camp\'s neutrals by puller, ally and no one inside slot..slot+45, the pulled wave\'s deaths and who of the other team took them', () => {
    const out = run([...base,
        line(171, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=5 camp=13 np=5 nd=200'),
        line(180, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=3 camp=13 np=3 nd=150'),
        line(214, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=none camp=13 np=5 nd=600'),
        // at slot + 45 (the window's end is exclusive), another camp, the other team's log: not counted.
        line(215, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=5 camp=13 np=5 nd=100'),
        line(175, 'neutral_death team=2 kind=neutral x=0 y=0 hp=0.05 by=5 camp=12 np=5 nd=100'),
        line(176, 'neutral_death team=3 kind=neutral x=-2400 y=-8400 hp=0.05 by=6 camp=13 np=6 nd=100'),
        // the pulled wave: two die near the camp in the puller's log, one denied; one 801 away is not the pull's.
        line(185, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=5'),
        line(190, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=none'),
        line(191, 'own_creep_death team=2 kind=melee x=-2415 y=-7601 hp=0.05 by=none'),
        // in the other team's log: their core's last hit, their deny of it (ours to them), no one's, and one after slot + 30.
        line(186, 'creep_death team=3 kind=melee x=-2415 y=-7602 hp=0.05 by=6'),
        line(187, 'creep_death team=3 kind=melee x=-2415 y=-7602 hp=0.05 by=deny'),
        line(188, 'creep_death team=3 kind=melee x=-2415 y=-7602 hp=0.05 by=9'),
        line(201, 'creep_death team=3 kind=melee x=-2415 y=-7602 hp=0.05 by=6'),
    ]);
    assert.deepStrictEqual(out.map(r => [r.pid, r.camp, r.slot, r.n_ours, r.n_puller, r.n_none, r.own_died, r.own_denied, r.them_took, r.them_core]),
        [[5, 13, 170, 2, 1, 1, 2, 1, 2, 1]]);
});

test('back-to-back pulls of one camp split their windows at the next slot, so no death counts twice; a slot after 720 s reads null neutrals', () => {
    const out = run([
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(165, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=170 res=ok why=ok'),
        line(195, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=198 res=ok why=ok'),
        line(180, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=5 camp=13 np=5 nd=100'),
        // at the second slot: the second pull's, not both.
        line(198, 'neutral_death team=2 kind=neutral x=-2400 y=-8400 hp=0.05 by=5 camp=13 np=5 nd=100'),
        line(199, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=none'),
        line(725, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=730 res=ok why=ok'),
    ]);
    assert.deepStrictEqual(out.map(r => [r.slot, r.n_puller, r.own_died]), [[170, 1, 0], [198, 1, 1], [730, null, 0]]);
});

test('a build without neutral_death reads null neutrals, not zero, while the wave columns still count', () => {
    const out = run([...base, line(185, 'own_creep_death team=2 kind=melee x=-2415 y=-7602 hp=0.05 by=none')]);
    assert.deepStrictEqual(out.map(r => [r.n_ours, r.n_none, r.own_died]), [[null, null, 1]]);
});
