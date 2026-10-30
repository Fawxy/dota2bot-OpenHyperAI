'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { checkGame, LINEUPS } = require('../lineup_check');

/** A log with lineup A's ten bots, the given --set line, optional ev=state lines and a stop at `stop`. */
function log({ set, states = 0, stop = 1200.4, swap = false, ours }) {
    const lines = [`10/28 12:00:00 [DOTACTL] t=-90 ev=start worktree=w mode=bots human=none timescale=8 seed=30 set="${set}"`];
    let pid = 0;
    for (const team of [2, 3]) {
        LINEUPS.A[team].forEach((hero, i) => {
            const pos = swap && team === 2 && i < 2 ? 2 - i : i + 1;
            lines.push(`10/28 12:00:01 [VScript] [HEV] t=-90.000 ev=bot pid=${pid++} hero=${hero} team=${team} schema=2 skill=0.750 build=abc1234+dirty pos=${pos}${ours ? ` ours=${ours}` : ''}`);
        });
    }
    for (let i = 0; i < states; i++) lines.push(`10/28 12:00:02 [VScript] [HEV] t=10.000 ev=state pid=0 state=laning`);
    lines.push(`10/28 12:09:00 [DOTACTL] t=${stop} ev=stop`);
    return lines.join('\n');
}

test('a valid game of each arm passes', () => {
    assert.deepStrictEqual(checkGame(log({ set: 'Humaniser.Enable=false,Humaniser.States.Enable=false' }), { lineup: 'A', arm: 'off', build: 'abc1234' }), []);
    assert.deepStrictEqual(checkGame(log({ set: 'Humaniser.States.Teams=all,Humaniser.Lane.OwnLaningThink=all', states: 3 }), { lineup: 'A', arm: 'on', build: 'abc1234' }), []);
});

test('every --set key of the arm is required (ER-001 review finding 10)', () => {
    const off = checkGame(log({ set: 'Humaniser.Enable=false' }), { lineup: 'A', arm: 'off', build: 'abc1234' });
    assert.match(off.join('; '), /lacks Humaniser\.States\.Enable=false/);
    const on = checkGame(log({ set: 'Humaniser.States.Teams=all', states: 3 }), { lineup: 'A', arm: 'on', build: 'abc1234' });
    assert.match(on.join('; '), /lacks Humaniser\.Lane\.OwnLaningThink=all/);
});

test('a wrong position, build, missing state layer or early stop is reported', () => {
    const p = checkGame(log({ set: 'Humaniser.States.Teams=all,Humaniser.Lane.OwnLaningThink=all', swap: true, stop: 900 }), { lineup: 'A', arm: 'on', build: 'fff0000' });
    const s = p.join('; ');
    assert.match(s, /luna team 2 pos 2/);
    assert.match(s, /build abc1234\+dirty/);
    assert.match(s, /ev=state 0/);
    assert.match(s, /stopped at t=900/);
});

test('an extra --set key fails the arm (an Enable=false on ON is a different arm)', () => {
    const p = checkGame(log({ set: 'Humaniser.States.Teams=all,Humaniser.Lane.OwnLaningThink=all,Humaniser.Enable=false', states: 3 }), { lineup: 'A', arm: 'on', build: 'abc1234' });
    assert.match(p.join('; '), /has extra Humaniser\.Enable=false/);
});

test('a remote arm is told apart by the ev=bot ours field (no --set)', () => {
    const arms = { on: { set: [], states: false, ours: { CoreLastHit: true } }, off: { set: [], states: false, ours: { CoreLastHit: false } } };
    const on = log({ set: '', ours: 'CoreLastHit:1,LeaveCoreCreep:1' });
    assert.deepStrictEqual(checkGame(on, { lineup: 'A', arm: 'on', build: 'abc1234', arms }), []);
    assert.match(checkGame(on, { lineup: 'A', arm: 'off', build: 'abc1234', arms }).join('; '), /10 bots lack ours CoreLastHit:0/);
    assert.match(checkGame(log({ set: '' }), { lineup: 'A', arm: 'off', build: 'abc1234', arms }).join('; '), /no ours field/);
});

test('an arm may expect its own build stamp (a remote arm is its own commit)', () => {
    const arms = { off: { set: [], states: false, build: 'abc1234' }, on: { set: [], states: false, build: 'def5678' } };
    assert.deepStrictEqual(checkGame(log({ set: '' }), { lineup: 'A', arm: 'off', build: 'zzz', arms }), []);
    assert.match(checkGame(log({ set: '' }), { lineup: 'A', arm: 'on', build: 'abc1234', arms }).join('; '), /build abc1234/);
});
