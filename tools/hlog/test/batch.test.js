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
    // Interim look: the same pooled row judged at alpha 0.025 widens the CI from the same SE and df, so a lo just
    // above 0 at 95% falls below it (t 2.306 -> 2.752 at df 8).
    const look = { m: { all: { delta: 3, se: 1.25, df: 8, lo: 3 - 2.306 * 1.25, hi: 3 + 2.306 * 1.25 } } };
    const vs = { rule: 'delta', metric: 'm', met: { lo: { gt: 0 } } };
    assert.strictEqual(bar(vs, [], look).result, 'met');
    const atLook = bar({ ...vs, alpha: 0.025 }, [], look);
    assert.strictEqual(atLook.result, 'not met');
    assert.match(atLook.value, /\+3\.0 \[-0\.4, 6\.4\] \(97\.5% CI\)/);
    // Without a df the 95% path would still meet lo > 0 (nf.js' own bounds); at an alpha the bounds are NaN, so not met.
    const noDf = { m: { all: { delta: 3, se: 1.25, df: NaN, lo: 0.5, hi: 5.5 } } };
    assert.strictEqual(bar(vs, [], noDf).result, 'met');
    assert.strictEqual(bar({ ...vs, alpha: 0.025 }, [], noDf).result, 'not met', 'no df: NaN bounds, not met');
    // An alpha outside (0, 1) (2.5 typed for 2.5%) must not collapse the CI onto the delta and pass the bar.
    assert.strictEqual(bar({ ...vs, alpha: 2.5 }, [], look).result, 'not met');
    // Guard rail against the batch's own MDE (slice 5): harm beyond it is not met; no MDE (OFF SD 0 or missing) is never met.
    const gr = { rule: 'delta', metric: 'm', met: { delta: { ge: '-mde' } } };
    assert.strictEqual(bar(gr, [], { m: { all: { delta: -1, lo: -3, hi: 1, mde: 2 } } }).result, 'met');
    assert.strictEqual(bar(gr, [], { m: { all: { delta: -2.5, lo: -4, hi: -1, mde: 2 } } }).result, 'not met');
    assert.strictEqual(bar(gr, [], { m: { all: { delta: 0, lo: -1, hi: 1, mde: NaN } } }).result, 'not met');
    assert.strictEqual(bar({ ...gr, met: { delta: { le: 'mde' } } }, [], { m: { all: { delta: 2.5, mde: 2 } } }).result, 'not met');
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

// batch.js main against a fake dotactl: FAKE_PLAN lists one outcome per call (ok, fail, curfew, badlineup); the child gets a temp
// home, so the manifest and the bank stay out of the real ~/.dotactl.
const { spawnSync } = require('child_process');
const FAKE = `'use strict';
const fs = require('fs'), path = require('path');
const { LINEUPS, SEEDS } = require(${JSON.stringify(path.resolve(__dirname, '../lineup_check'))});
const dir = process.env.FAKE_DIR, args = process.argv.slice(2);
const opt = k => args[args.indexOf(k) + 1];
const n = fs.existsSync(path.join(dir, 'n')) ? Number(fs.readFileSync(path.join(dir, 'n'), 'utf8')) : 0;
fs.writeFileSync(path.join(dir, 'n'), String(n + 1));
fs.appendFileSync(path.join(dir, 'calls.jsonl'), JSON.stringify(args) + '\\n');
const what = JSON.parse(process.env.FAKE_PLAN)[n] || 'ok';
if (what === 'curfew') { console.log('testing is closed by the user'); process.exit(1); }
if (what === 'fail') { console.log('console down'); process.exit(1); }
const lineup = Object.keys(SEEDS).find(k => String(SEEDS[k]) === opt('--seed'));
const sets = args.filter((a, i) => args[i - 1] === '--set');
const bots = [];
for (const team of [2, 3]) LINEUPS[lineup][team].forEach((h, i) => bots.push({ pid: bots.length, hero: what === 'badlineup' && !bots.length ? 'axe' : h, team, pos: i + 1 }));
const log = path.join(dir, opt('--label') + '-' + n + '.log');
fs.writeFileSync(log, [\`10/29 10:00:00 [DOTACTL] ev=start worktree=w mode=bots timescale=8 seed=\${opt('--seed')}\${sets.length ? \` set="\${sets.join(',')}"\` : ''}\`,
    ...bots.map(b => \`10/29 10:00:02 [VScript] [HEV] t=-90.000 ev=bot pid=\${b.pid} hero=\${b.hero} team=\${b.team} schema=2 build=abc1234 pos=\${b.pos}\`),
    ...(sets.length ? [] : ['10/29 10:00:03 [VScript] [HEV] t=0.000 ev=state pid=0 state=lane']),
    ...bots.map(b => \`10/29 10:00:04 [VScript] [HEV] t=1.000 ev=snap pid=\${b.pid} x=0 y=0 alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 kills=0 deaths=0 mode=laning d=0.3 act=2 gold=600\`),
    \`10/29 10:09:00 [DOTACTL] t=\${Number(opt('--until').split(':')[0]) * 60 + 0.5} ev=stop\`].join('\\n'));
console.log('log: ' + log);
`;

function runBatch(spec, fakePlan, dir) {
    const home = path.join(dir, 'home');
    fs.mkdirSync(home, { recursive: true });
    fs.writeFileSync(path.join(dir, 'fake.js'), FAKE);
    const file = path.join(dir, 'spec.json');
    fs.writeFileSync(file, JSON.stringify({ ...spec, dotactl: path.join(dir, 'fake.js') }));
    const r = spawnSync(process.execPath, [path.resolve(__dirname, '../batch.js'), file], { encoding: 'utf8',
        env: { ...process.env, HOME: home, USERPROFILE: home, FAKE_DIR: dir, FAKE_PLAN: JSON.stringify(fakePlan) } });
    const read = f => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n').filter(Boolean) : []);
    return { status: r.status, out: r.stdout + r.stderr, calls: read(path.join(dir, 'calls.jsonl')).map(JSON.parse),
        manifest: read(path.join(home, '.dotactl', 'batches', `${spec.name}.manifest`)),
        bank: read(path.join(home, '.dotactl', 'bank.jsonl')).map(JSON.parse) };
}

const BSPEC = { ...SPEC, name: 'bt', lineups: ['A', 'B'], until: '1:00' };

test('batch main: a failed game is retried once, --build only until the first success, valid games banked', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const r = runBatch(BSPEC, ['fail', 'ok', 'fail', 'ok', 'ok', 'ok'], dir);
    assert.strictEqual(r.status, 0, r.out);
    assert.deepStrictEqual(r.calls.map(a => a.includes('--build')), [true, true, false, false, false, false],
        'the retried first game builds again');
    assert.deepStrictEqual(r.calls.map(a => a[a.indexOf('--label') + 1]), ['bt_A_on_1', 'bt_A_on_1', 'bt_A_off_1', 'bt_A_off_1', 'bt_B_off_2', 'bt_B_on_2']);
    assert.ok(r.calls.every(a => path.isAbsolute(a[a.indexOf('--worktree') + 1])), 'worktree passed as an absolute path');
    assert.strictEqual(r.manifest.filter(l => l.startsWith('status=fail')).length, 2);
    assert.deepStrictEqual(r.bank.map(e => e.label).sort(), ['bt_A_off_1', 'bt_A_on_1', 'bt_B_off_2', 'bt_B_on_2']);
});

test('batch main: two failures stop the batch (exit 1); a re-run resumes after the ok games', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const r = runBatch(BSPEC, ['ok', 'fail', 'fail'], dir);
    assert.strictEqual(r.status, 1, r.out);
    assert.strictEqual(r.bank.length, 0);
    fs.unlinkSync(path.join(dir, 'calls.jsonl'));
    fs.unlinkSync(path.join(dir, 'n'));
    const again = runBatch(BSPEC, [], dir);
    assert.strictEqual(again.status, 0, again.out);
    assert.deepStrictEqual(again.calls.map(a => a[a.indexOf('--label') + 1]), ['bt_A_off_1', 'bt_B_off_2', 'bt_B_on_2']);
    assert.ok(again.calls[0].includes('--build'), 'the first game of a resumed run builds');
    assert.strictEqual(again.bank.length, 4);
});

test('batch main: the curfew stops it with exit 3; a usage error is exit 2', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const r = runBatch(BSPEC, ['ok', 'curfew'], dir);
    assert.strictEqual(r.status, 3, r.out);
    assert.strictEqual(r.calls.length, 2);
    assert.strictEqual(r.bank.length, 0);
    assert.strictEqual(spawnSync(process.execPath, [path.resolve(__dirname, '../batch.js')]).status, 2);
    const bad = path.join(dir, 'bad.json');
    fs.writeFileSync(bad, JSON.stringify({ name: 'x' }));
    assert.strictEqual(spawnSync(process.execPath, [path.resolve(__dirname, '../batch.js'), bad]).status, 2);
});

test('batch main: a game that fails lineup_check is not banked and the batch exits 1', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const r = runBatch(BSPEC, ['ok', 'badlineup', 'ok', 'ok'], dir);
    assert.strictEqual(r.status, 1, r.out);
    assert.match(r.out, /check bt_A_off_1 +axe team 2 pos 1/);
    assert.deepStrictEqual(r.bank.map(e => e.label).sort(), ['bt_A_on_1', 'bt_B_off_2', 'bt_B_on_2']);
});

test('remote batch: each game is a job on its arm\'s pushed commit, arms interleaved as locally', () => {
    const { plan, remoteJob } = require('../batch');
    const spec = { name: 's5', remote: true, until: '10:00', lineups: ['A', 'B'], arms: {
        on: { branch: 'remote/lion/s5-on', sha: 'a'.repeat(40) }, off: { branch: 'remote/lion/s5-off', sha: 'b'.repeat(40) } } };
    const games = plan(spec);
    assert.deepStrictEqual(games.map(g => g.label), ['s5_A_on_1', 's5_A_off_1', 's5_B_off_2', 's5_B_on_2']);
    const off = remoteJob(spec, games[1]);
    assert.deepStrictEqual(off, { branch: 'remote/lion/s5-off', sha: 'b'.repeat(40), until: '10:00', seed: 30, timescale: 8, label: 's5_A_off_1' });
    assert.strictEqual(remoteJob(spec, games[2]).seed, 8);
});

test('remote batch: runRemote saves the log, surfaces the reason, stops on a curfew and gives up on a silent host', async () => {
    const { runRemote, remoteJob } = require('../batch');
    const fsx = require('fs'), osx = require('os'), px = require('path');
    const logs = fsx.mkdtempSync(px.join(osx.tmpdir(), 'rb-'));
    const spec = { until: 600, arms: { on: { branch: 'remote/lion/x', sha: 'a'.repeat(40) } } };
    const game = { label: 'x_A_on_1', seed: 30, arm: 'on' };
    assert.strictEqual(remoteJob(spec, game).until, '10:00', 'a numeric until goes out as M:SS');
    const res = (status, body) => ({ ok: status < 400, status, json: async () => body, arrayBuffer: async () => Buffer.from(body.text || '') });
    // A host answering in order: submit, then each poll.
    const host = answers => async (url, o) => answers.shift()(url, o);
    const opts = extra => ({ poll: 0, sleepFn: async () => {}, logs, ...extra });
    const ok = await runRemote({ host: 'h', token: 't' }, spec, game, opts({ fetchFn: host([
        () => res(201, { id: 'j1', state: 'queued' }), () => res(200, { state: 'running' }), () => res(200, { state: 'done' }),
        url => (assert.match(url, /\/jobs\/j1\/files\/game\.log$/), res(200, { text: 'LOG' }))]) }));
    assert.ok(ok.ok && fsx.readFileSync(ok.log, 'utf8') === 'LOG' && ok.log.endsWith('-x_A_on_1.log'));
    const curfew = await runRemote({ host: 'h', token: 't' }, spec, game, opts({ fetchFn: host([
        () => res(201, { id: 'j2', state: 'queued' }),
        () => res(200, { state: 'failed', reason: 'testing is closed by the user from 30/10 until they reopen it' })]) }));
    assert.ok(!curfew.ok && curfew.curfew && /closed by the user/.test(curfew.out));
    const failed = await runRemote({ host: 'h', token: 't' }, spec, game, opts({ fetchFn: host([
        () => res(201, { id: 'j3', state: 'queued' }), () => res(200, { state: 'failed', reason: 'dotactl run exited 1' })]) }));
    assert.ok(!failed.ok && !failed.curfew && /exited 1/.test(failed.out));
    const silent = await runRemote({ host: 'h', token: 't' }, spec, game, opts({ maxBadPolls: 3, fetchFn: host([
        () => res(201, { id: 'j4', state: 'queued' }), () => res(500, {}), () => res(429, {}), () => { throw new Error('down'); }]) }));
    assert.ok(!silent.ok && /no state in 3 polls/.test(silent.out));
    const refused = await runRemote({ host: 'h', token: 't' }, spec, game, opts({ fetchFn: host([() => res(403, { error: 'forbidden' })]) }));
    assert.ok(!refused.ok && refused.out === 'submit 403 forbidden');
});

// Review 2026-10-30 eval-cost cc9740e L4, M2: the stop-when-decided wiring.
test('batch main: with er, a bar decided not met stops after the first pair, and lineup_check and the bank still run', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const er = path.join(dir, 'er.json');
    fs.writeFileSync(er, JSON.stringify({ bars: [{ id: 'H1', rule: 'each', metric: 'lua_ours', max: -1 }] }));
    const r = runBatch({ ...BSPEC, er }, [], dir);
    assert.strictEqual(r.status, 0, r.out);
    assert.match(r.out, /decide: bar not met: H1/);
    assert.strictEqual(r.calls.length, 2, 'stopped before the second pair');
    assert.deepStrictEqual(r.bank.map(e => e.label).sort(), ['bt_A_off_1', 'bt_A_on_1']);
    // Without er the same batch runs every game.
    const dir2 = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    assert.strictEqual(runBatch(BSPEC, [], dir2).calls.length, 4);
});

test('batch main: an er path that does not load is a usage error before any game', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'batch-'));
    const r = runBatch({ ...BSPEC, er: path.join(dir, 'missing.json') }, [], dir);
    assert.strictEqual(r.status, 2, r.out);
    assert.strictEqual(r.calls.length, 0);
});

test('batch decided: judged only with er and both arms; an error while judging goes on', () => {
    const { decided } = require('../batch');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dec-'));
    const man = path.join(dir, 'm.manifest');
    fs.writeFileSync(man, 'status=ok label="a" seed=8 arm=on lineup=B log="/x.log"\n');
    let calls = 0;
    const stop = () => { calls++; return { stop: true, reason: 'r' }; };
    assert.strictEqual(decided({ er: 'e.json' }, man, [], stop), false, 'one arm only');
    fs.appendFileSync(man, 'status=ok label="b" seed=8 arm=off lineup=B log="/y.log"\n');
    assert.strictEqual(decided({}, man, [], stop), false, 'no er');
    assert.strictEqual(calls, 0);
    assert.strictEqual(decided({ er: 'e.json' }, man, [], stop), true);
    assert.strictEqual(decided({ er: 'e.json' }, man, [], () => { throw new Error('bad log'); }), false);
});
