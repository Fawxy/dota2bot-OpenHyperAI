'use strict';
// The shared episodes (queries/fragments/ep_*.sql) and the timeline that shows them (@timeline, `hlog.js timeline`).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { Store } = require('../store');
const { secs, timelineRows, timelineText } = require('../hlog');

const HLOG = path.join(__dirname, '../hlog.js');
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const BOT_LANE = [3000, -6200];
const JUNGLE = [2500, -3500];
const DIRE_FOUNTAIN = [7020, 6345];

/**
 * Radiant luna (pid 0, pos 1) and lich (pid 1, pos 5) against Dire axe (pid 5, pos 1), all in the bot lane from 0:00:
 *   luna   retreat 20-25 and 28-30 (the next retreat second within 3 s: one bout), and 45-46 (another); attacks axe at 50, 51 and 62; with lich,
 *          at 100-102, when axe dies
 *   axe    answers at 53; 30% HP at 62; 20% at 100-102, dies at 102 (no snapshots to 140, then at its fountain)
 *   lich   a stack trip 150-170 (in the jungle 151-169) and a rune trip from 190 with no end
 */
function gameLines({ direTid = true } = {}) {
    const out = [
        line(-90, 'bot pid=0 hero=luna team=2 pos=1'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=axe team=3 pos=1'),
    ];
    const snap = (t, pid, o) => line(t, `snap pid=${pid} x=${o.p[0]} y=${o.p[1]} alive=1 hp=${o.hp ?? 100} deaths=${o.deaths ?? 0}`
        + ` mode=${o.mode ?? 'laning'}${o.tid ? ` tid=${o.tid}` : ''}`);
    for (let t = 0; t <= 200; t++) {
        const retreat = (t >= 20 && t <= 25) || (t >= 28 && t <= 30) || (t >= 45 && t <= 46);
        const luna = [50, 51, 62].includes(t) || (t >= 100 && t <= 102) ? 'h5' : undefined;
        out.push(snap(t, 0, { p: BOT_LANE, mode: retreat ? 'retreat' : 'laning', tid: luna }));
        const away = t >= 151 && t <= 169;
        out.push(snap(t, 1, { p: away ? JUNGLE : BOT_LANE, mode: away ? 'farm' : 'laning', tid: t >= 100 && t <= 102 ? 'h5' : undefined }));
        if (t > 102 && t < 140) continue;
        const axe = t >= 140 ? { p: DIRE_FOUNTAIN, deaths: 1 } : { p: [BOT_LANE[0] + 300, BOT_LANE[1]], hp: t === 62 ? 30 : t >= 100 ? 20 : 100 };
        out.push(snap(t, 5, { ...axe, tid: direTid && t === 53 ? 'h0' : undefined }));
    }
    out.push(line(150, 'job pid=1 job=stack phase=start why=trigger'), line(170, 'job pid=1 job=stack phase=end why=ok'));
    out.push(line(190, 'job pid=1 job=rune phase=start why=trigger'));
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

function storeOf(lines, label = 'tl_A_rad_1') {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-tl-'));
    const file = path.join(dir, `2026-11-23T00-00-00-${label}.log`);
    fs.writeFileSync(file, lines.join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return { store, file: path.resolve(file), dir };
}

const EPISODES = `WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games),
ep_win AS (SELECT -1e9 AS lo, 1e9 AS hi),
-- include: ep_retreat
-- include: ep_exchange
-- include: ep_kill
-- include: ep_job
-- include: ep_visit
done AS (SELECT 1)
`;

test('episodes: one definition each, from what happened', () => {
    const { store } = storeOf(gameLines());
    const q = sql => store.query(EPISODES + sql).map(r => ({ ...r }));
    assert.deepStrictEqual(q('SELECT pid, t, gap, n, open FROM ep_death'), [{ pid: 5, t: 102, gap: 102, n: 1, open: 0 }]);
    assert.deepStrictEqual(q('SELECT pid, t0, t1, secs FROM ep_retreat ORDER BY t0'),
        [{ pid: 0, t0: 20, t1: 30, secs: 9 },{ pid: 0, t0: 45, t1: 46, secs: 2 }]);
    assert.deepStrictEqual(q('SELECT a, b, t0, t1, a_secs, b_secs FROM ep_exchange ORDER BY t0, a'), [
        { a: 0, b: 5, t0: 50, t1: 53, a_secs: 2, b_secs: 1 },
        { a: 0, b: 5, t0: 62, t1: 62, a_secs: 1, b_secs: 0 },
        { a: 0, b: 5, t0: 100, t1: 102, a_secs: 3, b_secs: 0 },
        { a: 1, b: 5, t0: 100, t1: 102, a_secs: 3, b_secs: 0 },
    ]);
    assert.deepStrictEqual(q('SELECT team, tpid, t0, t1, hpmin, killed FROM ep_kill ORDER BY t0'), [
        { team: 2, tpid: 5, t0: 62, t1: 62, hpmin: 30, killed: 0 },
        { team: 2, tpid: 5, t0: 100, t1: 102, hpmin: 20, killed: 1 },
    ]);
    assert.deepStrictEqual(q('SELECT pid, src, job, t0, t1, why FROM ep_job ORDER BY t0'), [
        { pid: 1, src: 'job', job: 'stack', t0: 150, t1: 170, why: 'ok' },
        { pid: 1, src: 'job', job: 'rune', t0: 190, t1: null, why: null },
    ]);
    assert.deepStrictEqual(q("SELECT pid, lane, t0, t1 FROM ep_visit ORDER BY pid, t0"), [
        { pid: 0, lane: 'bot', t0: 0, t1: 200 },
        { pid: 1, lane: 'bot', t0: 0, t1: 150 },
        { pid: 1, lane: 'bot', t0: 170, t1: 200 },
        { pid: 5, lane: 'bot', t0: 0, t1: 102 },
    ]);
    store.close();
});

test('ep_death: a hero whose snapshots stop over 3 s before the log ends is dead there', () => {
    const lines = gameLines().filter(l => !/pid=5 /.test(l) || Number(l.match(/t=(-?[\d.]+)/)[1]) <= 102);
    const { store } = storeOf(lines);
    assert.deepStrictEqual(store.query(EPISODES + 'SELECT pid, t, open FROM ep_death').map(r => ({ ...r })), [{ pid: 5, t: 102, open: 1 }]);
    store.close();
});

test('timeline: rows by kind, the window takes any overlap, a lane, a hero as either party', () => {
    const { store, file } = storeOf(gameLines());
    const rows = o => timelineRows(store, file, o);
    const kinds = rows({}).reduce((n, r) => ({ ...n, [r.kind]: (n[r.kind] || 0) + 1 }), {});
    assert.deepStrictEqual(Object.keys(kinds).sort(), ['death', 'exchange', 'job', 'kill_try', 'mode', 'not_logged', 'retreat', 'state', 'visit']);
    const death = rows({ kind: 'death' }).find(r => r.kind === 'death');
    assert.strictEqual(death.detail, 'died in laning; attacked by luna, lich');
    assert.strictEqual(death.lane, 'bot');
    assert.deepStrictEqual(rows({ kind: 'retreat', from: '0:22', to: 23 }).filter(r => r.t !== null).map(r => [r.t, r.t1]), [[20, 30]]);
    assert.deepStrictEqual(rows({ kind: 'kill_try' }).filter(r => r.t !== null).map(r => [r.hero, r.t, r.detail]), [
        ['luna', 62, 'on axe by luna: lived, low 30'],
        ['luna', 100, 'on axe by luna, lich: killed'],
    ]);
    // axe is the other party of luna's exchanges, so they are axe's rows too.
    assert.strictEqual(rows({ kind: 'exchange', hero: 'axe' }).filter(r => r.t !== null).length, 4);
    assert.deepStrictEqual(rows({ kind: 'job' }).filter(r => r.t !== null).map(r => r.detail), ['stack: ok', 'rune: no end logged']);
    assert.strictEqual(rows({ lane: 'top' }).filter(r => r.t !== null).length, 0);
    store.close();
});

test('timeline: what the log cannot show is a row, whatever the lane, hero or window', () => {
    const { store, file } = storeOf(gameLines({ direTid: false }).filter(l => !/pid=5 .*tid=/.test(l)));
    const lack = timelineRows(store, file, { lane: 'top', from: 0, to: 1, hero: 'lich' }).filter(r => r.kind === 'not_logged').map(r => r.detail);
    assert.deepStrictEqual(lack.sort(), [
        'Dire: no attack target (tid) in the log, so its attacks are not seen',
        'Dire: no casts in the log', 'Dire: no creep deaths in the log', 'Dire: no decisions in the log',
        'Radiant: no casts in the log', 'Radiant: no creep deaths in the log', 'Radiant: no decisions in the log',
    ]);
    // A kind filter keeps only what it asked about.
    assert.deepStrictEqual(timelineRows(store, file, { kind: 'retreat' }).filter(r => r.kind === 'not_logged'), []);
    assert.strictEqual(timelineRows(store, file, { kind: 'cast' }).filter(r => r.kind === 'not_logged').length, 2);
    store.close();
});

test('timeline: a misspelt filter is an error, not an empty answer', () => {
    const { store, file } = storeOf(gameLines());
    assert.throws(() => timelineRows(store, file, { kind: 'retreats' }), /no kind retreats/);
    assert.throws(() => timelineRows(store, file, { lane: 'safe' }), /no lane safe/);
    assert.throws(() => timelineRows(store, file, { hero: 'lion' }), /no hero lion in that game; of: luna lich axe/);
    store.close();
});

test('timeline text: one line a row, oldest first; no gap line when the kinds asked need nothing missing', () => {
    const { store, file } = storeOf(gameLines());
    const text = timelineText(timelineRows(store, file, { kind: 'death,retreat' }), {}).split('\n');
    assert.deepStrictEqual(text.map(l => l.replace(/\s+/g, ' ')), [
        '0:20-0:30 bot R1 luna retreat hp 100 to 100 (low 100)',
        '0:45-0:46 bot R1 luna retreat hp 100 to 100 (low 100)',
        '1:42 bot D1 axe death died in laning; attacked by luna, lich',
    ]);
    store.close();
});

test('timeline CLI: a log path, filters and m:ss times', () => {
    const { file, dir } = storeOf(gameLines());
    const db = path.join(dir, 's.sqlite');
    const r = spawnSync(process.execPath, [HLOG, 'timeline', file, '--hero', 'axe', '--kind', 'death', '--db', db], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /1:42 +bot +D1 axe +death +died in laning/);
    const bad = spawnSync(process.execPath, [HLOG, 'timeline', file, '--kind', 'deaths', '--db', db], { encoding: 'utf8' });
    assert.strictEqual(bad.status, 1);
    assert.match(bad.stderr, /no kind deaths/);
    assert.deepStrictEqual([secs('5:20'), secs('-0:30'), secs('90'), secs(undefined)], [320, -30, 90, undefined]);
    assert.throws(() => secs('soon'), /no game time/);
});

/**
 * Radiant luna (pid 0) retreats from 0:10 with falling HP and dies at 20.4 (its last snapshot, a fraction past the second; HP 8),
 * back at its fountain at 41. Dire axe (pid 5) stands 300 from it the whole time. No attack target is logged.
 */
function dyingLines() {
    const out = [line(-90, 'bot pid=0 hero=luna team=2 pos=1'), line(-90, 'bot pid=5 hero=axe team=3 pos=1')];
    const snap = (t, pid, p, hp, deaths, mode) => line(t, `snap pid=${pid} x=${p[0]} y=${p[1]} alive=1 hp=${hp} deaths=${deaths} mode=${mode}`);
    for (let t = 0; t <= 60; t++) {
        out.push(snap(t, 5, [BOT_LANE[0] + 300, BOT_LANE[1]], 100, 0, 'laning'));
        if (t < 20) out.push(snap(t, 0, BOT_LANE, t < 10 ? 100 : 100 - 5 * (t - 9), 0, t < 10 ? 'laning' : 'retreat'));
        if (t === 20) out.push(snap(20.4, 0, BOT_LANE, 8, 0, 'retreat'));
        if (t >= 41) out.push(snap(t, 0, [-6700, -6700], 100, 1, 'laning'));
    }
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

const only = (rows, kind) => rows.filter(r => r.kind === kind).map(r => ({ ...r }));
const pick = (r, keys) => Object.fromEntries(keys.map(k => [k, r[k]]));

test('timeline columns: an exchange says who was struck, the seconds each way, both heroes\' HP and the gap between them', () => {
    const { store, file } = storeOf(gameLines());
    const ex = only(timelineRows(store, file, { kind: 'exchange' }), 'exchange');
    const cols = ['t', 't1', 'secs', 'hero', 'other_pid', 'other', 'a_secs', 'b_secs', 'hp0', 'hp1', 'ohp0', 'ohp1', 'outcome', 'd0', 'd1'];
    assert.deepStrictEqual(ex.filter(r => r.pid === 0).map(r => pick(r, cols)), [
        { t: 50, t1: 53, secs: 3, hero: 'luna', other_pid: 5, other: 'axe', a_secs: 2, b_secs: 1, hp0: 100, hp1: 100, ohp0: 100, ohp1: 100, outcome: 'answered', d0: 300, d1: 300 },
        { t: 62, t1: 62, secs: 0, hero: 'luna', other_pid: 5, other: 'axe', a_secs: 1, b_secs: 0, hp0: 100, hp1: 100, ohp0: 30, ohp1: 30, outcome: 'none_back', d0: 300, d1: 300 },
        { t: 100, t1: 102, secs: 2, hero: 'luna', other_pid: 5, other: 'axe', a_secs: 3, b_secs: 0, hp0: 100, hp1: 100, ohp0: 20, ohp1: 20, outcome: 'none_back', d0: 300, d1: 300 },
    ]);
    store.close();
});

test('timeline columns: a kill try is its first attacker on the target, with the target\'s low', () => {
    const { store, file } = storeOf(gameLines());
    const rows = only(timelineRows(store, file, { kind: 'kill_try' }), 'kill_try');
    // lich joins luna's second try but luna struck first at that second, so the row is luna's.
    assert.deepStrictEqual(rows.map(r => pick(r, ['t', 't1', 'secs', 'hero', 'other_pid', 'other', 'hpmin', 'outcome', 'hp0', 'ohp0', 'ohp1', 'd0'])), [
        { t: 62, t1: 62, secs: 0, hero: 'luna', other_pid: 5, other: 'axe', hpmin: 30, outcome: 'lived', hp0: 100, ohp0: 30, ohp1: 30, d0: 300 },
        { t: 100, t1: 102, secs: 2, hero: 'luna', other_pid: 5, other: 'axe', hpmin: 20, outcome: 'killed', hp0: 100, ohp0: 20, ohp1: 20, d0: 300 },
    ]);
    store.close();
});

test('timeline columns: retreat, job and visit say how they ended; a death has no end', () => {
    const { store, file } = storeOf(gameLines());
    const rows = timelineRows(store, file, {});
    assert.deepStrictEqual(only(rows, 'retreat').map(r => pick(r, ['t', 't1', 'secs', 'hp0', 'hp1', 'hpmin', 'outcome', 'd0', 'd1', 'other_pid'])), [
        { t: 20, t1: 30, secs: 10, hp0: 100, hp1: 100, hpmin: 100, outcome: 'lived', d0: 300, d1: 300, other_pid: null },
        { t: 45, t1: 46, secs: 1, hp0: 100, hp1: 100, hpmin: 100, outcome: 'lived', d0: 300, d1: 300, other_pid: null },
    ]);
    assert.deepStrictEqual(only(rows, 'job').map(r => pick(r, ['detail', 'secs', 'outcome', 'd0', 'd1'])), [
        // axe is at its fountain by then: sqrt(4020^2 + 12545^2) from lich in the bot lane.
        { detail: 'stack: ok', secs: 20, outcome: 'ok', d0: 13173, d1: 13173 },
        { detail: 'rune: no end logged', secs: null, outcome: 'no_end', d0: 13173, d1: null },
    ]);
    const visits = only(rows, 'visit').map(r => pick(r, ['hero', 't', 't1', 'secs', 'outcome', 'hp0', 'd0']));
    assert.deepStrictEqual(visits.filter(r => r.hero !== 'luna' && r.t === 0), [
        { hero: 'lich', t: 0, t1: 150, secs: 150, outcome: 'laning', hp0: 100, d0: 300 },
        { hero: 'axe', t: 0, t1: 102, secs: 102, outcome: 'dead', hp0: 100, d0: 300 },
    ]);
    assert.deepStrictEqual(only(rows, 'death').map(r => pick(r, ['hero', 'secs', 'outcome', 'hp0', 'hp1', 'd0', 'd1', 'other_pid'])),
        [{ hero: 'axe', secs: null, outcome: 'died', hp0: 20, hp1: null, d0: 300, d1: null, other_pid: null }]);
    // Not an episode: the extra columns stay empty.
    assert.deepStrictEqual(only(rows, 'mode').filter(r => r.detail === 'farm').map(r => pick(r, ['hero', 'secs', 'hp0', 'd0', 'outcome'])),
        [{ hero: 'lich', secs: 18, hp0: null, d0: null, outcome: null }]);
    store.close();
});

test('timeline columns: a retreat that ends in a death, and a visit that ends dead', () => {
    const { store, file } = storeOf(dyingLines());
    const rows = timelineRows(store, file, {});
    assert.deepStrictEqual(only(rows, 'retreat').map(r => pick(r, ['t', 't1', 'secs', 'hp0', 'hp1', 'hpmin', 'outcome'])),
        [{ t: 10, t1: 20, secs: 10, hp0: 95, hp1: 8, hpmin: 8, outcome: 'died' }]);
    assert.deepStrictEqual(only(rows, 'visit').filter(r => r.hero === 'luna').map(r => pick(r, ['t', 't1', 'outcome'])), [{ t: 0, t1: 20, outcome: 'dead' }]);
    store.close();
});

test('timeline: a death is in a window that ends at its second, though its time is a fraction past it', () => {
    const { store, file } = storeOf(dyingLines());
    const deaths = o => only(timelineRows(store, file, { kind: 'death', ...o }), 'death').map(r => r.t);
    assert.deepStrictEqual(deaths({}), [20.4]);
    assert.deepStrictEqual(deaths({ to: '0:20' }), [20.4]);
    assert.deepStrictEqual(deaths({ to: 19 }), []);
    assert.deepStrictEqual(deaths({ from: 20 }), [20.4]);
    store.close();
});

test('timeline: --pid shows a hero\'s rows as either party, as --hero does', () => {
    const { store, file } = storeOf(gameLines());
    const rows = o => timelineRows(store, file, { kind: 'exchange,kill_try,death', ...o }).filter(r => r.t !== null).map(r => `${r.hero} ${r.kind} ${r.t}`);
    // axe (pid 5) struck nothing, yet is the other party of every exchange and kill try, and died.
    assert.deepStrictEqual(rows({ pid: 5 }).sort(), rows({ hero: 'axe' }).sort());
    assert.strictEqual(rows({ pid: 5 }).length, 7);
    // lich (pid 1) struck in one exchange, and is among the attackers of the kill try that luna's row names first.
    assert.deepStrictEqual(rows({ pid: 1 }).sort(), ['axe death 102', 'lich exchange 100', 'luna kill_try 100']);
    store.close();
});

test('timeline: run label columns, and which side of the label\'s seat each row is on', () => {
    const rad = storeOf(gameLines(), 'h2hlift1_A_owncore-rad_3');
    const rows = timelineRows(rad.store, rad.file, { kind: 'retreat,death' }).filter(r => r.t !== null);
    const label = ['batch', 'lineup', 'arm', 'seat', 'rep'];
    assert.deepStrictEqual(pick(rows[0], label), { batch: 'h2hlift1', lineup: 'A', arm: 'owncore', seat: 'rad', rep: 3 });
    assert.deepStrictEqual([...new Set(rows.map(r => `${r.hero} ${r.team} ${r.side}`))].sort(), ['axe 3 opp', 'luna 2 test']);
    rad.store.close();
    const dire = storeOf(gameLines(), 'base1_B_restdire_2');
    const d = timelineRows(dire.store, dire.file, { kind: 'retreat,death' }).filter(r => r.t !== null);
    assert.deepStrictEqual(pick(d[0], label), { batch: 'base1', lineup: 'B', arm: 'rest', seat: 'dire', rep: 2 });
    assert.deepStrictEqual([...new Set(d.map(r => `${r.hero} ${r.side}`))].sort(), ['axe test', 'luna opp']);
    dire.store.close();
    const stock = storeOf(gameLines(), 'base1_A_stock_1');
    const s = timelineRows(stock.store, stock.file, { kind: 'retreat' }).filter(r => r.t !== null);
    assert.deepStrictEqual(pick(s[0], [...label, 'side']), { batch: 'base1', lineup: 'A', arm: 'stock', seat: null, rep: 1, side: null });
    stock.store.close();
});

test('timeline query: param batch is an exact run name, and arm narrows it', () => {
    const store = new Store(':memory:');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-batch-'));
    for (const label of ['base1_A_offrad_1', 'base1_A_restrad_1', 'h2hbase1_A_offrad_1', 'base1_smoke1', 'base10_A_offrad_1']) {
        const f = path.join(dir, `2026-11-23T00-00-00-${label}.log`);
        fs.writeFileSync(f, gameLines().join('\n') + '\n');
        store.ingest(f);
    }
    store.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '../queries/timeline.sql'), 'utf8');
    const labels = p => [...new Set(store.query(sql, { kind: 'death', ...p }).filter(r => r.t !== null).map(r => `${r.batch} ${r.arm}`))].sort();
    assert.deepStrictEqual(labels({ batch: 'base1' }), ['base1 off', 'base1 rest']);
    assert.deepStrictEqual(labels({ batch: 'base1', arm: 'rest' }), ['base1 rest']);
    assert.deepStrictEqual(labels({ batch: 'h2hbase1' }), ['h2hbase1 off']);
    // like still names a path fragment (a label with no lineup or seat has no batch), and with neither no game is read.
    assert.deepStrictEqual(labels({ like: '%base1_smoke1%' }), ['null null']);
    assert.deepStrictEqual(labels({}), []);
    store.close();
});

test('a query can count timeline rows: include the fragment after WITH and end on a bare SELECT', () => {
    const { store } = storeOf(gameLines(), 'base1_A_offrad_1');
    const r = store.query(`WITH
-- include: timeline_rows
SELECT arm, side, count(*) AS n, sum(outcome = 'killed') AS killed FROM timeline_rows WHERE kind = 'kill_try' GROUP BY arm, side`,
    { batch: 'base1' }).map(x => ({ ...x }));
    assert.deepStrictEqual(r, [{ arm: 'off', side: 'test', n: 2, killed: 1 }]);
    store.close();
});

test('CLI: m:ss as well as seconds in --p times, --pid, and an argument that cannot be read is an error', () => {
    const { file, dir } = storeOf(dyingLines(), 'base1_A_offrad_1');
    const db = path.join(dir, 's.sqlite');
    const run = (...a) => spawnSync(process.execPath, [HLOG, ...a, '--db', db, '--no-ingest'], { encoding: 'utf8' });
    assert.strictEqual(spawnSync(process.execPath, [HLOG, 'ingest', file, '--db', db], { encoding: 'utf8' }).status, 0);
    const count = (...p) => JSON.parse(run('q', "WITH\n-- include: timeline_rows\nSELECT kind, t FROM timeline_rows WHERE kind = 'retreat'", '--p', 'batch=base1', ...p, '--json').stdout).length;
    assert.strictEqual(count(), 1);
    assert.strictEqual(count('--p', 'from=0:20'), 1);
    assert.strictEqual(count('--p', 'from=0:21'), 0);
    assert.strictEqual(count('--p', 'to=0:09'), 0);
    assert.strictEqual(count('--p', 'to=10'), 1);
    assert.strictEqual(run('timeline', file, '--pid', '5', '--kind', 'death').stdout.includes('luna'), false);
    for (const bad of [['--from', 'soon'], ['--lan', 'bot'], ['--from'], ['--pid', 'x']]) {
        const r = run('timeline', file, ...bad);
        assert.strictEqual(r.status, 1, bad.join(' '));
        assert.ok(r.stderr.length > 0);
    }
    assert.strictEqual(run('q', '@timeline', '--p', 'batch=base1', '--p', 'from=soon').status, 1);
});

/**
 * Radiant lich (pid 1) pulls in the bot lane (lane 3); Dire jakiro (pid 6) is a switched-off puller in the top lane (lane 1),
 * writing shadow lines. Each lich slot is one case:
 *   77   not wanted (lane)
 *   107  wanted and held back twice: busy, then enemy-near (the last line is the row)
 *   137  started at 120, trip ends ok at 140; a later go=0 line for the same slot does not replace it
 *   167  started at 150, trip cut at 158 (cancelled:retreat)
 *   197  started at 180, no end logged
 *   227  go=1 at 210, but only a stack job starts then: not its trip
 *   257  not wanted (lane)
 * jakiro: slot 77 wanted (off), slot 107 not wanted; the same slot as lich's 107 stays its own row. lich's `deny` line at slot
 * 107 is another kind's row; its `decider` and `shadow` lines are no decisions.
 */
function decisionLines({ dire = true } = {}) {
    const pull = (t, pid, lane, slot, f) => line(t, `choice pid=${pid} kind=pull lane=${lane} slot=${slot} ${f}`);
    const job = (t, f) => line(t, `job pid=1 ${f}`);
    const out = [
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=6 hero=jakiro team=3 pos=5'),
        pull(60, 1, 3, 77, 'want=0 go=0 why=lane src=own'),
        pull(90, 1, 3, 107, 'want=1 go=0 why=busy src=own'),
        pull(95, 1, 3, 107, 'want=1 go=0 why=enemy-near src=own'),
        line(96, 'choice pid=1 kind=deny lane=3 slot=107 want=1 go=0 why=far src=own'),
        line(97, 'choice pid=1 kind=decider held=- win=farm'),
        line(98, 'choice pid=1 kind=shadow want=1 go=0'),
        pull(120, 1, 3, 137, 'want=1 go=1 src=own'), job(120, 'job=pull phase=start why=trigger'),
        pull(125, 1, 3, 137, 'want=1 go=0 why=busy src=own'),
        job(140, 'job=pull phase=end why=ok'),
        pull(150, 1, 3, 167, 'want=1 go=1 src=own'), job(150, 'job=pull phase=start why=trigger'),
        job(158, 'job=pull phase=end why=cancelled:retreat'),
        pull(180, 1, 3, 197, 'want=1 go=1 src=own'), job(180, 'job=pull phase=start why=trigger'),
        pull(210, 1, 3, 227, 'want=1 go=1 src=own'), job(210, 'job=stack phase=start why=trigger'),
        pull(240, 1, 3, 257, 'want=0 go=0 why=lane src=own'),
    ];
    if (dire) out.push(pull(61, 6, 1, 77, 'want=1 go=0 why=off src=shadow'), pull(91, 6, 1, 107, 'want=0 go=0 why=off src=shadow'));
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

test('timeline decisions: one row per opportunity, its outcome from the choice line and the trip it started', () => {
    const { store, file } = storeOf(decisionLines());
    const rows = only(timelineRows(store, file, { kind: 'decision' }), 'decision');
    assert.deepStrictEqual(rows.map(r => pick(r, ['hero', 'what', 'slot', 't', 't1', 'lane', 'outcome', 'why', 'secs'])), [
        { hero: 'lich', what: 'pull', slot: 77, t: 60, t1: null, lane: 'bot', outcome: 'unwanted', why: 'lane', secs: null },
        { hero: 'jakiro', what: 'pull', slot: 77, t: 61, t1: null, lane: 'top', outcome: 'off', why: null, secs: null },
        { hero: 'jakiro', what: 'pull', slot: 107, t: 91, t1: null, lane: 'top', outcome: 'unwanted', why: 'off', secs: null },
        { hero: 'lich', what: 'pull', slot: 107, t: 95, t1: null, lane: 'bot', outcome: 'refused', why: 'enemy-near', secs: null },
        { hero: 'lich', what: 'deny', slot: 107, t: 96, t1: null, lane: 'bot', outcome: 'refused', why: 'far', secs: null },
        { hero: 'lich', what: 'pull', slot: 137, t: 120, t1: 140, lane: 'bot', outcome: 'done', why: null, secs: 20 },
        { hero: 'lich', what: 'pull', slot: 167, t: 150, t1: 158, lane: 'bot', outcome: 'cut', why: 'cancelled:retreat', secs: 8 },
        { hero: 'lich', what: 'pull', slot: 197, t: 180, t1: null, lane: 'bot', outcome: 'no_end', why: null, secs: null },
        { hero: 'lich', what: 'pull', slot: 227, t: 210, t1: null, lane: 'bot', outcome: 'no_start', why: null, secs: null },
        { hero: 'lich', what: 'pull', slot: 257, t: 240, t1: null, lane: 'bot', outcome: 'unwanted', why: 'lane', secs: null },
    ]);
    assert.deepStrictEqual(timelineText(timelineRows(store, file, { kind: 'decision', from: 95, to: 160 }), {}).split('\n').map(l => l.replace(/\s+/g, ' ')), [
        '1:35 bot R5 lich decision pull: refused (enemy-near), slot 1:47',
        '1:36 bot R5 lich decision deny: refused (far), slot 1:47',
        '2:00-2:20 bot R5 lich decision pull: done, slot 2:17',
        '2:30-2:38 bot R5 lich decision pull: cut (cancelled:retreat), slot 2:47',
    ]);
    store.close();
});

test('timeline decisions: a team with no choice lines says so, for kind decision only', () => {
    const { store, file, dir } = storeOf(decisionLines({ dire: false }));
    const lack = o => timelineRows(store, file, o).filter(r => r.kind === 'not_logged').map(r => r.detail);
    assert.deepStrictEqual(lack({ kind: 'decision' }), ['Dire: no decisions in the log']);
    assert.deepStrictEqual(lack({ kind: 'job' }), []);
    store.close();
    const r = spawnSync(process.execPath, [HLOG, 'timeline', file, '--kind', 'decision', '--db', path.join(dir, 's.sqlite')], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /not logged: Dire: no decisions in the log/);
    assert.match(r.stdout, /3:30 +bot +R5 lich +decision pull: go, no job start logged, slot 3:47/);
});

test('@decisions: outcomes and reasons by arm and side, each a share of its side\'s opportunities', () => {
    const { store } = storeOf(decisionLines(), 'dec1_A_onrad_1');
    const sql = fs.readFileSync(path.join(__dirname, '../queries/decisions.sql'), 'utf8');
    const rows = p => store.query(sql, { batch: 'dec1', ...p }).map(r => [r.arm, r.side, r.what, r.outcome, r.why, r.n, r.share, r.games]);
    assert.deepStrictEqual(rows({}), [
        ['on', 'opp', 'pull', 'unwanted', 'off', 1, 0.5, 1],
        ['on', 'opp', 'pull', 'off', null, 1, 0.5, 1],
        ['on', 'test', 'deny', 'refused', 'far', 1, 1, 1],
        ['on', 'test', 'pull', 'unwanted', 'lane', 2, 0.286, 1],
        ['on', 'test', 'pull', 'refused', 'enemy-near', 1, 0.143, 1],
        ['on', 'test', 'pull', 'no_start', null, 1, 0.143, 1],
        ['on', 'test', 'pull', 'done', null, 1, 0.143, 1],
        ['on', 'test', 'pull', 'cut', 'cancelled:retreat', 1, 0.143, 1],
        ['on', 'test', 'pull', 'no_end', null, 1, 0.143, 1],
    ]);
    // A window keeps the decisions taken in it (a trip that crosses its edge too), and what narrows to one kind.
    assert.deepStrictEqual(rows({ what: 'pull', from: 130, to: 200 }).map(r => r.slice(1, 7)), [
        ['test', 'pull', 'done', null, 1, 0.333],
        ['test', 'pull', 'cut', 'cancelled:retreat', 1, 0.333],
        ['test', 'pull', 'no_end', null, 1, 0.333],
    ]);
    store.close();
});
