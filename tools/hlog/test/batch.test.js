'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { plan, runArgs, seconds } = require('../batch');
const bank = require('../bank');
const { readManifest, expandPath } = require('../manifest');
const { health, bar, cond } = require('../er');

const OFF = ['Humaniser.Enable=false', 'Humaniser.States.Enable=false'];
const SPEC = { name: 's1', worktree: 'w', build: 'abc1234', lineups: ['A', 'B', 'C', 'A', 'B'], until: '20:00',
    arms: { on: { set: [], states: true }, off: { set: OFF, states: false } } };

test('batch plan: slice 1 order (s1.sh): arms alternate per rep, seeds per lineup', () => {
    assert.deepStrictEqual(plan(SPEC).map(g => g.label), ['s1_A_on_1', 's1_A_off_1', 's1_B_off_2', 's1_B_on_2', 's1_C_on_3',
        's1_C_off_3', 's1_A_off_4', 's1_A_on_4', 's1_B_on_5', 's1_B_off_5']);
    assert.deepStrictEqual(plan(SPEC).map(g => g.seed), [30, 30, 8, 8, 25, 25, 30, 30, 8, 8]);
});

test('batch plan: three arms rotate by one each rep (shared OFF arm)', () => {
    const p = plan({ ...SPEC, lineups: ['A', 'B', 'C'], arms: { off: { set: OFF }, f1: { set: ['Ours.F1=true'] }, f2: { set: ['Ours.F2=true'] } } });
    assert.deepStrictEqual(p.map(g => g.arm), ['off', 'f1', 'f2', 'f1', 'f2', 'off', 'f2', 'off', 'f1']);
});

test('batch runArgs: --build only when asked, one --set per key', () => {
    const [on, off] = plan(SPEC);
    const a = runArgs(SPEC, on, true);
    assert.ok(a.includes('--build'));
    assert.deepStrictEqual(a.slice(a.indexOf('--seed'), a.indexOf('--seed') + 2), ['--seed', '30']);
    const b = runArgs(SPEC, off, false);
    assert.ok(!b.includes('--build'));
    assert.deepStrictEqual(b.filter((x, i) => b[i - 1] === '--set'), OFF);
    assert.strictEqual(seconds('20:00'), 1200);
    assert.strictEqual(seconds(600), 600);
});

/** A minimal dotactl test log. */
function log(set, build = 'abc1234', stop = 1200.4) {
    return [`10/29 10:00:00 [DOTACTL] ev=start worktree=w mode=bots human=none timescale=8 seed=30${set ? ` set="${set}"` : ''}`,
        '10/29 10:00:01 [Client] Build: 10938',
        `10/29 10:00:02 [VScript] [HEV] t=-90.000 ev=bot pid=0 hero=luna team=2 schema=2 build=${build} pos=1`,
        '10/29 10:00:02 [VScript] [HEV] t=-90.000 ev=snap pid=0 x=0 y=0 alive=1 hp=100',
        `10/29 10:09:00 [DOTACTL] t=${stop} ev=stop`].join('\n');
}

test('bank: facts from the log, add replaces by path, query filters, prune drops missing logs', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bank-'));
    const logA = path.join(dir, '2026-10-29T10-00-00-x_A_off_1.log'), logB = path.join(dir, '2026-10-29T10-10-00-x_A_on_1.log');
    fs.writeFileSync(logA, log(OFF.join(',')));
    fs.writeFileSync(logB, log('', 'abc1234', 605.1));
    const man = path.join(dir, 'x.manifest');
    fs.writeFileSync(man, `status=ok label="x_A_off_1" seed=30 arm=off lineup=A log="${logA}"\nstatus=fail label="x_A_on_1" seed=30 arm=on lineup=A rc=1 log=""\nstatus=ok label="x_A_on_1" seed=30 arm=on lineup=A log="${logB}"\n`);
    const file = path.join(dir, 'bank.jsonl');
    const d = bank.describe(log(OFF.join(',')));
    assert.deepStrictEqual([d.build, d.set, d.patch, d.until, d.timescale, d.evs], ['abc1234', OFF.join(','), '10938', 1200, 8, ['bot', 'snap']]);
    bank.add(bank.entriesFor(man, { validUntil: 600 }), file);
    bank.add(bank.entriesFor(man), file); // re-adding replaces, so validUntil is gone
    const all = bank.load(file);
    assert.strictEqual(all.length, 2);
    assert.ok(all.every(e => e.validUntil === undefined && e.batch === 'x' && e.date === '2026-10-29'));
    assert.deepStrictEqual(bank.query(all, { arm: 'off', seed: '30', until: '1200' }).map(e => e.label), ['x_A_off_1']);
    assert.deepStrictEqual(bank.query(all, { until: 1200 }).map(e => e.label), ['x_A_off_1'], 'the on game stopped at 10:05');
    assert.deepStrictEqual(bank.query(all, { has: 'lua_error' }), []);
    fs.unlinkSync(logB);
    assert.deepStrictEqual(bank.prune(file).map(e => e.label), ['x_A_on_1']);
    assert.strictEqual(bank.load(file).length, 1);
});

test('manifest: ok lines only, ~ expanded', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'man-'));
    const man = path.join(dir, 'm.manifest');
    fs.writeFileSync(man, 'status=ok label="a" seed=8 arm=on lineup=B log="~/x.log"\nvoid label=b\n');
    const g = readManifest(man);
    assert.strictEqual(g.length, 1);
    assert.strictEqual(g[0].seed, 8);
    assert.strictEqual(g[0].log, expandPath('~/x.log'));
    assert.ok(!g[0].log.startsWith('~'));
});

test('er health: highest n per site, ours vs oha.*, squelch only right after an error', () => {
    const text = [
        '[VScript] [HEV] t=10.000 ev=lua_error pid=1 where=Lane.PreThink msg="x" n=1',
        '[VScript] [HEV] t=20.000 ev=lua_error pid=1 where=Lane.PreThink msg="x" n=7',
        '[VScript] [HEV] t=30.000 ev=lua_error pid=2 where=oha.mode_farm.Think msg="y" n=3',
        '[VScript] Script Runtime Error: error in error handling',
        'Message count limit of 10 hit',
        '[VScript] something else',
        'Message count limit of 10 hit',
        '[H:tasks] support engine bundle=ok',
    ].join('\n');
    const h = health(text);
    assert.deepStrictEqual([h.lua_ours, h.lua_oha, h.console, h.squelch, h.bundle_ok], [7, 3, 1, 1, 1]);
});

test('er bars: each, mean and the three-way delta rule', () => {
    const g = (label, arm, v) => ({ label, arm, health: { lua_ours: v }, flat: {} });
    const games = [g('a', 'on', 0), g('b', 'on', 5), g('c', 'off', 9)];
    assert.strictEqual(bar({ rule: 'each', metric: 'lua_ours', max: 0 }, games, {}).result, 'not met');
    assert.strictEqual(bar({ rule: 'each', metric: 'lua_ours', arms: ['off'], max: 10 }, games, {}).result, 'met');
    assert.strictEqual(bar({ rule: 'mean', metric: 'lua_ours', cmp: 'on<=off' }, games, {}).result, 'met');
    const t = { m: { all: { delta: -5.6, lo: -8.1, hi: -3.0 } } };
    const g1 = { rule: 'delta', metric: 'm', met: { lo: { gt: -5 } }, notMet: { hi: { lt: -5 } } };
    assert.strictEqual(bar(g1, [], t).result, 'inconclusive');
    assert.strictEqual(bar(g1, [], { m: { all: { delta: -9, lo: -12, hi: -6 } } }).result, 'not met');
    assert.strictEqual(bar(g1, [], { m: { all: { delta: 0, lo: -2, hi: 2 } } }).result, 'met');
    assert.strictEqual(bar({ rule: 'delta', metric: 'm', met: { lo: { gt: 0 } } }, [], t).result, 'not met');
    assert.ok(cond({ lo: { le: 0 }, hi: { ge: 1 } }, { lo: 0, hi: 1 }));
});

test('er gaps: a gap with a death, one without, and an early stop with and without an enemy kill after it', () => {
    const { gaps } = require('../er');
    const s = (t, deaths, kills = 0, hp = 50) => ({ t, deaths, kills, hp });
    const game = { bots: {
        0: { pid: 0, hero: 'luna', team: 2, snaps: [s(0, 0), s(1, 0), s(10, 1), s(11, 1), s(15, 1), s(20, 1)] },
        1: { pid: 1, hero: 'sk', team: 3, snaps: [s(0, 0), s(1, 0, 0), s(5, 0, 1), s(20, 0, 1)] },
        2: { pid: 2, hero: 'lion', team: 3, snaps: [s(0, 0), s(12, 0)] },
    } };
    const r = gaps(game);
    assert.deepStrictEqual([r.gaps, r.withDeath], [6, 1]);
    assert.strictEqual(r.other.length, 5);
    assert.match(r.early.join(), /lion\[2\] last t=12 hp=50, enemy kills did not rise/);
});
