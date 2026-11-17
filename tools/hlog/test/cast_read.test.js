'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { readGame, tally, parseReady } = require('../cast_read');

test('cast read: members, casts in the window by class and aim, ready and unused', () => {
    // Low Dire pid 6 at t=100; Radiant hunters 1 and 2 attacked (hatk), 3 did not.
    const ch = (hpid, hatk) => ({ label: 'a', side: 'ours', pid: 6, t: 100, died: 1, hpid, hpos: hpid, hatk });
    const chances = [ch(1, 1), ch(2, 1), ch(3, 0)];
    const snaps = [];
    for (const sec of [98, 99, 100, 101, 102]) {
        snaps.push({ pid: 6, team: 3, sec, x: 1000, y: 0, alive: 1, rdy: null });
        snaps.push({ pid: 7, team: 3, sec, x: 2000, y: 0, alive: 1, rdy: null });
        snaps.push({ pid: 1, team: 2, sec, x: 500, y: 0, alive: 1, rdy: sec === 100 ? 'bane_nightmare:k;bane_brain_sap:d;bane_fiends_grip:u' : null });
        // pid 2 has no snapshot at 100: its ready list falls back to 99's. (A snapshot without rdy means nothing ready.)
        if (sec !== 100) snaps.push({ pid: 2, team: 2, sec, x: 400, y: 0, alive: 1, rdy: sec === 99 ? 'zuus_arc_lightning:d' : null });
    }
    const casts = [
        { pid: 1, t: 100.4, ab: 'bane_nightmare', cl: 'k', x: 1050, y: 0 }, // at the target
        { pid: 1, t: 101.2, ab: 'bane_brain_sap', cl: 'd', x: 1990, y: 10 }, // at another enemy
        { pid: 2, t: 96.0, ab: 'zuus_arc_lightning', cl: 'd', x: 1000, y: 0 }, // before the window
        { pid: 2, t: 102, ab: 'zuus_static', cl: 'o', x: null, y: null },
        { pid: 3, t: 100, ab: 'x', cl: 'd', x: 1000, y: 0 }, // not a member
    ];
    const [f] = readGame(chances, casts, snaps);
    assert.deepStrictEqual(f.members.map((m) => m.pid), [1, 2]);
    assert.deepStrictEqual(f.members[0].casts.map((c) => [c.ab, c.at]), [['bane_nightmare', 'target'], ['bane_brain_sap', 'enemy']]);
    assert.deepStrictEqual(f.members[0].unused, [{ n: 'bane_fiends_grip', c: 'u' }]);
    // pid 2's ready list is read from the second before t; its arc was cast before the window, so it is unused.
    assert.deepStrictEqual(f.members[1].unused, [{ n: 'zuus_arc_lightning', c: 'd' }]);
    assert.deepStrictEqual(f.members[1].casts.map((c) => c.at), ['none']);
    const t = tally([f], 2).two;
    assert.strictEqual(t.fights, 0.5);
    assert.strictEqual(t.died, 1);
    assert.strictEqual(t.casts.k, 1);
    assert.strictEqual(t.atTarget, 0.5);
    assert.strictEqual(t.kReady, 1);
    assert.strictEqual(t.kUsed, 1);
    assert.deepStrictEqual([t.unused.k, t.unused.u, t.unused.d], [0, 1, 1]);
    assert.strictEqual(tally([f], 2).one.n, 0);
});

test('cast read: a chance nobody attacked is no fight; ready lists parse', () => {
    assert.deepStrictEqual(readGame([{ label: 'a', side: 'oha', pid: 1, t: 5, died: 0, hpid: 6, hpos: 1, hatk: 0 }], [], []), []);
    assert.deepStrictEqual(parseReady('a_b:k;c:d'), [{ n: 'a_b', c: 'k' }, { n: 'c', c: 'd' }]);
    assert.deepStrictEqual(parseReady(null), []);
});
