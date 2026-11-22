'use strict';
// The batch summary of `hlog.js timeline <batch> --count` (summary.js): its statistics and the counting of episode rows into per-game measures.
const test = require('node:test');
const assert = require('node:assert');
const { describe, welch, verdict, parsePos, summarise } = require('../summary');

const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} is not ${b}`);

test('welch: means, unpooled standard error and the 1.96 interval of a difference', () => {
    // a: mean 4, sample variance 4; b: mean 2, sample variance 2; se = sqrt(4/3 + 2/2)
    const d = welch([2, 4, 6], [1, 3]);
    assert.strictEqual(d.meanA, 4);
    assert.strictEqual(d.meanB, 2);
    assert.strictEqual(d.diff, 2);
    near(d.se, Math.sqrt(7 / 3));
    near(d.ci, 1.96 * Math.sqrt(7 / 3));
});

test('welch: unequal spreads are not pooled', () => {
    // pooled variance would be (2*0 + 2*9)/4 = 4.5, se 1.5; Welch gives sqrt(0/3 + 9/3) = sqrt(3)
    near(welch([5, 5, 5], [0, 3, 6]).se, Math.sqrt(3));
});

test('describe: a single value has no variance', () => {
    assert.ok(Number.isNaN(describe([7]).variance));
    assert.strictEqual(describe([7]).mean, 7);
});

test('verdict: * only when the diff beats its own interval and the floor of identical code', () => {
    const floor = { diff: 1, ci: 2 };
    assert.strictEqual(verdict({ diff: 5, ci: 1 }, floor), '*');
    assert.strictEqual(verdict({ diff: 5, ci: 6 }, floor), '', 'inside its own interval');
    assert.strictEqual(verdict({ diff: 2.5, ci: 1 }, floor), '', 'clear of 0 but inside the floor 1 ± 2');
    assert.strictEqual(verdict({ diff: -2.5, ci: 1 }, floor), '*', 'below the floor 1 ± 2 on the other side');
    assert.strictEqual(verdict({ diff: 5, ci: NaN }, floor), '', 'no interval, no mark');
});

test('parsePos: ranges and lists, and a bad one is an error', () => {
    assert.deepStrictEqual(parsePos('1-3'), [1, 2, 3]);
    assert.deepStrictEqual(parsePos('1,2,5'), [1, 2, 5]);
    assert.deepStrictEqual(parsePos(undefined), [1, 2, 3, 4, 5]);
    assert.throws(() => parsePos('3-1'));
    assert.throws(() => parsePos('0-2'));
});

const game = (file, arm, seat_team = 2) => ({ file, arm, seat_team });
const secs = (file, team, atk) => ({ file, game: 1, team, atk, atk_laning: 0, near700: 0 });

test('summarise: episodes count to the side and position they belong to, a retreat is clipped to the window', () => {
    const games = ['a1', 'a2', 'a3'].map(f => game(f, 'off')).concat(['b1', 'b2', 'b3'].map(f => game(f, 'x')));
    const eps = [];
    for (const f of ['b1', 'b2', 'b3']) {
        // the test side's pos 1 tries on an opp pos 2 and kills; the opp's pos 5 tries on test pos 1 (the pos filter drops it from "by")
        eps.push({ file: f, arm: 'x', side: 'test', kind: 'kill_try', pos: 1, tpos: 2, t: 100, t1: 110, outcome: 'killed' });
        eps.push({ file: f, arm: 'x', side: 'opp', kind: 'kill_try', pos: 5, tpos: 1, t: 200, t1: 210, outcome: 'lived' });
        eps.push({ file: f, arm: 'x', side: 'test', kind: 'retreat', pos: 1, t: 590, t1: 640 });
        eps.push({ file: f, arm: 'x', side: 'test', kind: 'death', pos: 4, t: 300 });
    }
    const s = summarise({ games, eps, secs: [], ref: 'off', pos: [1, 2, 3], from: 0, to: 600 });
    const row = (side, key) => s.blocks.find(b => b.side === side).rows.find(r => r.key === key);
    assert.strictEqual(row('test', 'kill_tries_by').a, 1);
    assert.strictEqual(row('test', 'kill_tries_by_killed').a, 1);
    assert.strictEqual(row('opp', 'kill_tries_by').a, 0, 'a pos 5 attacker is outside --pos 1-3');
    assert.strictEqual(row('test', 'kill_tries_on').a, 1, 'the opp try on test pos 1 counts against the test side');
    assert.strictEqual(row('opp', 'kill_tries_on').a, 1, 'the test try on opp pos 2');
    assert.strictEqual(row('test', 'retreat_secs').a, 10, '590 to 640 inside 0 to 600');
    assert.strictEqual(row('test', 'deaths').a, 0, 'a pos 4 death is outside --pos 1-3');
    assert.strictEqual(row('test', 'kill_tries_by_killed').n, 0, 'the reference arm has no try to divide by');
});

test('summarise: a share leaves out games with no denominator; hero seconds go to the side of the seat', () => {
    const games = ['a1', 'a2', 'a3'].map(f => game(f, 'off', 3)).concat(['b1', 'b2', 'b3'].map(f => game(f, 'x', 3)));
    const eps = [{ file: 'b1', arm: 'x', side: 'test', kind: 'exchange', pos: 1, t: 10, t1: 12, outcome: 'none_back' }];
    const s = summarise({ games, eps, secs: [secs('b1', 3, 30), secs('b1', 2, 8)], ref: 'off', pos: [1], from: 0, to: 600 });
    const row = (side, key) => s.blocks.find(b => b.side === side).rows.find(r => r.key === key);
    assert.strictEqual(row('test', 'struck_first_unanswered').n, 0, 'one game has an exchange, the reference arm has none');
    assert.strictEqual(row('test', 'struck_first_unanswered').thin, true);
    assert.strictEqual(row('test', 'attack_secs').a, 10, 'dire (team 3) is the test seat: 30 s over three games');
    assert.strictEqual(row('opp', 'attack_secs').a, 8 / 3);
});

test('summarise: no reference, a thin arm and a stock game are said plainly', () => {
    const none = summarise({ games: [game('a', 'x'), game('b', 'x'), game('c', 'x'), game('d', null, null)], eps: [], secs: [], ref: 'off', pos: [1], from: 0, to: 600 });
    assert.strictEqual(none.skipped, 1);
    assert.match(none.problems[0], /no reference arm off/);
    assert.deepStrictEqual(none.blocks.map(b => b.rows.length), [0, 0]);
    const thin = summarise({ games: ['a', 'b', 'c'].map(f => game(f, 'off')).concat([game('d', 'x'), game('e', 'x')]), eps: [], secs: [], ref: 'off', pos: [1], from: 0, to: 600 });
    assert.match(thin.problems[0], /arm x has 2 games.*fewer than 3/);
    const thinRef = summarise({ games: [game('a', 'off'), game('b', 'x')], eps: [], secs: [], ref: 'off', pos: [1], from: 0, to: 600 });
    assert.match(thinRef.problems[0], /reference arm off has 1 games.*no floor/);
});
