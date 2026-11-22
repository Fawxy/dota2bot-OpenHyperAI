'use strict';
// The persisted per-second table `hero_sec` (store.js `fillHeroSec`, queries/fragments/hero_sec_fill.sql), on the synthetic game
// of timeline.test.js: Radiant luna (pid 0) and lich (pid 1) against Dire axe (pid 5) in the bot lane.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const BOT_LANE = [3000, -6200];
const DIRE_FOUNTAIN = [7020, 6345];

/** luna attacks axe at 50 and 62; axe attacks luna at 53, is 300 units from the lane pair, and dies at 102 (no snapshots 103-139). */
function gameLines({ withAxe = true } = {}) {
    const out = [
        line(-90, 'bot pid=0 hero=luna team=2 pos=1'),
        line(-90, 'bot pid=1 hero=lich team=2 pos=5'),
        line(-90, 'bot pid=5 hero=axe team=3 pos=1'),
    ];
    const snap = (t, pid, p, o = {}) => line(t, `snap pid=${pid} x=${p[0]} y=${p[1]} alive=1 hp=${o.hp ?? 100} deaths=${o.deaths ?? 0} mode=laning${o.tid ? ` tid=${o.tid}` : ''}`);
    for (let t = 0; t <= 200; t++) {
        out.push(snap(t, 0, BOT_LANE, { tid: t === 50 || t === 62 ? 'h5' : undefined }));
        out.push(snap(t, 1, [BOT_LANE[0] + 100, BOT_LANE[1]]));
        if (!withAxe || (t > 102 && t < 140)) continue;
        out.push(t >= 140 ? snap(t, 5, DIRE_FOUNTAIN, { deaths: 1 })
            : snap(t, 5, [BOT_LANE[0] + 300, BOT_LANE[1]], { hp: t >= 100 ? 20 : 100, tid: t === 53 ? 'h0' : undefined }));
    }
    return out.sort((a, b) => Number(a.match(/t=(-?[\d.]+)/)[1]) - Number(b.match(/t=(-?[\d.]+)/)[1]));
}

function setup(lines = gameLines()) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-hs-'));
    const file = path.join(dir, '2026-11-23T00-00-00-hs_A_rad_1.log');
    fs.writeFileSync(file, lines.join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return { store, file, dir };
}

const row = (store, pid, sec) => ({ ...store.query('SELECT * FROM hero_sec WHERE pid = :pid AND sec = :sec', { pid, sec })[0] });

test('hero_sec holds ep_sec row for row, filled by the first query that names it', () => {
    const { store } = setup();
    const frag = store.query(`WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games),
ep_win AS (SELECT -1e9 AS lo, 1e9 AS hi),
-- include: ep_second
done AS (SELECT 1)
SELECT pid, team, pos, sec, x, y, hp, mode, live, life FROM ep_sec ORDER BY pid, sec`).map(r => ({ ...r }));
    assert.ok(frag.length > 400);
    assert.ok(frag.some(r => r.life === 1), 'axe has died once by its respawn');
    const hs = store.query('SELECT pid, team, pos, sec, x, y, hp, mode, live, life FROM hero_sec ORDER BY pid, sec').map(r => ({ ...r }));
    assert.deepStrictEqual(hs, frag);
});

test('hits is the enemy hero attacked that second; a pid of 0 is a target, not NULL', () => {
    const { store } = setup();
    store.fillHeroSec();
    assert.strictEqual(row(store, 0, 50).hits, 5);
    assert.strictEqual(row(store, 0, 51).hits, null);
    assert.strictEqual(row(store, 5, 53).hits, 0);
    assert.strictEqual(row(store, 5, 54).hits, null);
});

test('near and the 900 counts read the live heroes of that second only', () => {
    const { store } = setup();
    store.fillHeroSec();
    // luna, lich and axe stand 100 and 300 apart on the same lane
    assert.deepStrictEqual(['near', 'en900', 'al900'].map(k => row(store, 0, 10)[k]), [300, 1, 1]);
    assert.deepStrictEqual(['near', 'en900', 'al900'].map(k => row(store, 1, 10)[k]), [200, 1, 1]);
    // axe has no snapshot from 103 to 139: nothing near, whatever it was a second earlier
    assert.deepStrictEqual(['near', 'en900', 'al900'].map(k => row(store, 0, 120)[k]), [null, 0, 1]);
    // axe at its fountain is live but far away
    const far = row(store, 0, 150);
    assert.ok(far.near > 9000 && far.en900 === 0);
});

test('a game filled under the current rules is skipped; another version refills it', () => {
    const { store } = setup();
    assert.strictEqual(store.fillHeroSec(), 1);
    store.db.exec('UPDATE hero_sec SET hp = -5 WHERE pid = 0 AND sec = 10');
    assert.strictEqual(store.fillHeroSec(), 0);
    assert.strictEqual(row(store, 0, 10).hp, -5, 'a filled game is not rewritten');
    store.heroSecVersion = () => 'changed-fragment';
    assert.strictEqual(store.fillHeroSec(), 1);
    assert.strictEqual(row(store, 0, 10).hp, 100);
    assert.strictEqual(store.query('SELECT count(*) AS n FROM hero_sec WHERE hp = -5')[0].n, 0);
});

test('a re-ingested log leaves no rows of what it held before', () => {
    const { store, file } = setup();
    store.fillHeroSec();
    assert.ok(row(store, 5, 10).pid === 5);
    fs.writeFileSync(file, gameLines({ withAxe: false }).join('\n') + '\n');
    assert.strictEqual(store.ingest(file), true);
    // the new game takes the old game's id, so a stale stamp would also keep it from being refilled
    assert.strictEqual(store.query('SELECT count(*) AS n FROM hero_sec WHERE pid = 5')[0].n, 0);
    assert.strictEqual(store.query('SELECT count(DISTINCT pid) AS n FROM hero_sec')[0].n, 2);
    assert.strictEqual(store.query('SELECT count(*) AS n FROM hero_sec_games g JOIN games m USING (game_id)')[0].n, 1);
});

test('a pruned log leaves no rows', () => {
    const { store, file } = setup();
    store.fillHeroSec();
    fs.rmSync(file);
    store.prune();
    assert.strictEqual(store.db.prepare('SELECT count(*) AS n FROM hero_sec').get().n, 0);
    assert.strictEqual(store.db.prepare('SELECT count(*) AS n FROM hero_sec_games').get().n, 0);
});

test('@hero_seconds: the games asked for are filled, and its filters apply', () => {
    const { store } = setup();
    const rows = store.query(fs.readFileSync(path.join(__dirname, '../queries/hero_seconds.sql'), 'utf8'),
        { like: '%hs_A%', game: null, pid: 0, hero: null, lane: null, from: 48, to: 52 }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.hero, r.sec, r.hits]), [['luna', 48, null], ['luna', 49, null], ['luna', 50, 5], ['luna', 51, null], ['luna', 52, null]]);
    assert.strictEqual(rows[0].lane, 'bot');
    // a pattern naming no game fills nothing
    const none = new Store(':memory:');
    none.fillHeroSec({ like: '%nothing%' });
    assert.strictEqual(none.db.prepare('SELECT count(*) AS n FROM hero_sec').get().n, 0);
});
