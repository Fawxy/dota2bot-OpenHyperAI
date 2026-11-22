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

function storeOf(lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-tl-'));
    const file = path.join(dir, '2026-11-23T00-00-00-tl_A_rad_1.log');
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
        'Dire: no casts in the log', 'Dire: no creep deaths in the log',
        'Radiant: no casts in the log', 'Radiant: no creep deaths in the log',
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
