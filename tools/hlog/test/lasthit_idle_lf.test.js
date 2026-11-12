'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const near = 'p1d=100 p1r=150 p1t=0';

function rows(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-idle-')), 'a.log');
    fs.writeFileSync(f, lines.sort((a, b) => Number(a.match(/t=([\d.]+)/)[1]) - Number(b.match(/t=([\d.]+)/)[1])).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(fs.readFileSync(path.join(__dirname, '..', 'queries', 'lasthit_idle_lf.sql'), 'utf8'), { file: f, game: 1, until: 600, held: 0, ...params });
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

test('a creep our body lost while holding its swing is no violation; walking in, a stall or another why stays one, labelled', () => {
    const lh = (t, reason, x, msg, kind = 'lasthit', result = 'fail') =>
        line(t, `lh pid=1 kind=${kind} result=${result} reason=${reason} cx=${x} cy=100 msg="w=1.00 ${msg}"`);
    const lines = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(99, 'snap pid=1 x=0 y=0 alive=1 mode=laning'),
        line(100, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(100.03, 'taken_by_other', 10, 'why=wait'),
        line(110, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(110.1, 'denied', 0, 'why=range d=120'),
        line(120, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        line(121.5, 'lh pid=1 kind=lasthit result=fail reason=taken_by_other cx=0 cy=100 msg="w=3.00 why=wait"'),
        // Lost on a creep 200 away, a lost deny and one interrupted: another creep, or not lost to this one, so each death
        // stays a violation.
        line(130, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(130.03, 'taken_by_other', 200, 'why=wait'),
        line(140, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(140.03, 'taken_by_other', 0, 'why=wait', 'deny'),
        line(150, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(150.03, 'interrupted', 0, 'why=wait'),
        // The attempt ended 0.2 s before the death: it was over before the creep died.
        line(160, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(159.8, 'taken_by_other', 0, 'why=wait'),
        // It started 1 s after the death (w=1.00, ended 2 s after, under the stall cut it would otherwise meet): a later attempt.
        line(170, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        lh(172, 'taken_by_other', 0, 'why=wait'),
        // A lost attempt whose msg carries no why (killed during the wind-up) explains nothing.
        line(180, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        line(180.03, 'lh pid=1 kind=lasthit result=fail reason=taken_by_other cx=0 cy=100 msg="hp=40 pred=10"'),
    ];
    assert.deepStrictEqual(rows(lines).map(r => r.t), [110, 120, 130, 140, 150, 160, 170, 180]);
    assert.deepStrictEqual(rows(lines, { held: 1 }).map(r => [r.t, r.held]), [
        [100, 'wait'], [110, 'range'], [120, 'stall'], [130, null], [140, null], [150, null], [160, null], [170, null], [180, null],
    ]);
});

test('one lost attempt excuses only the nearest of two creeps dying beside it', () => {
    const out = rows([
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(99, 'snap pid=1 x=0 y=0 alive=1 mode=laning'),
        line(100, `creep_death team=2 kind=melee x=0 y=100 hp=0.1 by=none ${near}`),
        line(100.02, `creep_death team=2 kind=melee x=40 y=100 hp=0.1 by=none ${near}`),
        line(100.05, 'lh pid=1 kind=lasthit result=fail reason=taken_by_other cx=35 cy=100 msg="w=1.00 why=wait"'),
    ], { held: 1 });
    assert.deepStrictEqual(out.map(r => [r.t, r.held]), [[100, null], [100.02, 'wait']]);
});
