'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store, INGEST_VERSION, DECLARED, versionOf } = require('../store');

const QUERY = fs.readFileSync(path.join(__dirname, '../queries/stack_attempts.sql'), 'utf8');

function tmp() {
    return fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-store-'));
}

function log(dir, name, lines) {
    const f = path.join(dir, name);
    fs.writeFileSync(f, lines.join('\n') + '\n');
    return f;
}

const BOT = '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456';
const FACTS = [
    '10/30 07:59:58 [DOTACTL] ev=start worktree=oha-x mode=bots human=none timescale=8 seed=30 set="Ours.StackJob=true,Ours.X=1"',
    '10/30 08:00:01 [DOTACTL] t=-55.0 ev=lineup bots="10 bots [lion(rad)]" rad=5 dire=5 human=none',
];

test('column kinds: numeric only while every value parses; ? and absent are NULL; true/false are 1/0; lists stay text', () => {
    const dir = tmp();
    const s = new Store(':memory:', { views: null });
    s.ingest(log(dir, 'a.log', [BOT,
        '[HEV] t=1 ev=probe pid=1 a=1 b=? c=true n2=a:1:in:2,b:3:out:4',
        '[HEV] t=2 ev=probe pid=1 a=2 c=false']));
    assert.deepStrictEqual(s.query('SELECT a, b, c, n2 FROM ev_probe ORDER BY t').map(r => ({ ...r })),
        [{ a: 1, b: null, c: 1, n2: 'a:1:in:2,b:3:out:4' }, { a: 2, b: null, c: 0, n2: null }]);
    assert.strictEqual(s.colsOf('ev_probe').get('a'), 'num');
    // A later log with a non-numeric value marks the column text, but each value keeps its own type, so a view's
    // numeric comparison still means what it says on the numeric rows (SQLite compares '1' > 0 as text, true).
    s.ingest(log(dir, 'b.log', [BOT, '[HEV] t=3 ev=probe pid=1 a=x7']));
    assert.strictEqual(s.colsOf('ev_probe').get('a'), 'text');
    assert.deepStrictEqual(s.query('SELECT a, typeof(a) AS k FROM ev_probe ORDER BY t').map(r => [r.a, r.k]),
        [[1, 'integer'], [2, 'integer'], ['x7', 'text']]);
    assert.deepStrictEqual(s.query('SELECT t FROM ev_probe WHERE a > 1 AND a < 100').map(r => r.t), [2]);
    // A build sha keeps its leading zero (parse.js STRING_KEYS).
    assert.strictEqual(s.query('SELECT build FROM games LIMIT 1')[0].build, '0123456');
});

test('kinds survive a reopen, and a declared kind overrides inference', () => {
    const dir = tmp();
    const db = path.join(dir, 's.sqlite');
    let s = new Store(db, { views: null });
    s.ingest(log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']));
    s.close();
    s = new Store(db, { views: null, kinds: { ev_probe: { code: 'text' } } });
    s.ingest(log(dir, 'b.log', [BOT, '[HEV] t=2 ev=probe pid=1 a=hello code=42']));
    assert.strictEqual(s.colsOf('ev_probe').get('a'), 'text');
    assert.deepStrictEqual(s.query('SELECT code, typeof(code) AS k FROM ev_probe WHERE code IS NOT NULL').map(r => [r.code, r.k]), [['42', 'text']]);
});

test('games carry the run facts from [DOTACTL] lines, and the facts keep their own tables', () => {
    const s = new Store(':memory:', { views: null });
    s.ingest(log(tmp(), 'a.log', [...FACTS, BOT, '[HEV] t=5 ev=probe pid=1 a=1', '10/30 08:10:00 [DOTACTL] t=600.2 ev=stop state=post']));
    const g = s.query('SELECT * FROM games')[0];
    assert.deepStrictEqual([g.mode, g.seed, g.set, g.lineup, g.stop_t, g.bots], ['bots', 30, 'Ours.StackJob=true,Ours.X=1', '10 bots [lion(rad)]', 600.2, 1]);
    assert.strictEqual(s.query('SELECT state FROM dx_stop')[0].state, 'post');
});

test('team-wide events are stored once, as parse.js de-duplicates them', () => {
    const s = new Store(':memory:', { views: null });
    s.ingest(log(tmp(), 'a.log', [BOT,
        '[HEV] t=10 ev=mark by=0 text=here',
        '[HEV] t=10.3 ev=mark by=0 text=here',
        '[HEV] t=20 ev=mark by=0 text=here']));
    assert.deepStrictEqual(s.query('SELECT t FROM ev_mark ORDER BY t').map(r => r.t), [10, 20]);
});

test('a changed log is re-ingested in place; an unchanged one is skipped; a deleted one is pruned', () => {
    const dir = tmp();
    const s = new Store(':memory:', { views: null });
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    assert.strictEqual(s.ingest(f), true);
    assert.strictEqual(s.ingest(f), false);
    log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1', '[HEV] t=2 ev=probe pid=1 a=2']);
    fs.utimesSync(f, new Date(), new Date(Date.now() + 5000));
    assert.strictEqual(s.ingest(f), true);
    assert.deepStrictEqual(s.query('SELECT count(*) AS n FROM ev_probe')[0].n, 2);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM games')[0].n, 1);
    fs.rmSync(f);
    assert.deepStrictEqual(s.ingestAll([dir]).pruned, [f]);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM ev_probe')[0].n, 0);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM games')[0].n, 0);
});

test('stack view: stackCause rules, and the view opens on logs that never wrote the :59 fields', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    // An older build: ev=stack without box59 and friends. The view still opens (needs: adds the columns as NULL).
    s.ingestAll([log(dir, 'old.log', [BOT, '[HEV] t=100 ev=stack pid=1 min=1 res=not_stacked why=late camp=3 type=small after=?'])]);
    assert.deepStrictEqual(s.query('SELECT res, cause FROM stack_attempts').map(r => [r.res, r.cause]), [['not_stacked', null]]);
    s.ingestAll([log(dir, 'new.log', [BOT,
        '[HEV] t=110 ev=stack pid=1 min=1 res=stacked why=ok box59=0',
        '[HEV] t=170 ev=stack pid=1 min=2 res=failed why=3',
        '[HEV] t=230 ev=stack pid=1 min=3 res=not_stacked why=x box59=0 bot59=1',
        '[HEV] t=290 ev=stack pid=1 min=4 res=not_stacked why=x box59=2 bot59=0',
        '[HEV] t=350 ev=stack pid=1 min=5 res=not_stacked why=x box59=0 bot59=0 vis59=0 after=?',
        '[HEV] t=410 ev=stack pid=1 min=6 res=not_stacked why=x box59=0 bot59=0 vis59=0 after=3',
        '[HEV] t=470 ev=stack pid=1 min=7 res=not_stacked why=x box59=? bot59=0',
        '[HEV] t=530 ev=stack pid=1 min=8 res=skip why=busy'])]);
    const rows = s.query(QUERY, { until: 500 }).filter(r => r.file.endsWith('new.log')).map(r => [r.res, r.cause, r.n]);
    assert.deepStrictEqual(rows, [
        ['failed', '3', 1],
        ['not_stacked', null, 1],
        ['not_stacked', 'bot-in-box', 1],
        ['not_stacked', 'camp-in-box', 1],
        ['not_stacked', 'no-spawn', 1],
        ['not_stacked', 'unseen', 1],
        ['stacked', null, 1],
    ]);
});

test('[HEV] text quoted inside a [DOTACTL] cmd line is not an event and does not split the game', () => {
    const s = new Store(':memory:', { views: null });
    s.ingest(log(tmp(), 'a.log', [...FACTS, BOT,
        '[HEV] t=100 ev=probe pid=1 a=1',
        '10/30 08:02:00 [DOTACTL] t=100.5 ev=cmd cmd=status out="[HEV] t=0.3 ev=snap pid=1 x=0 | [HEV] t=0.3 ev=probe pid=1 a=9"',
        '[HEV] t=101 ev=probe pid=1 a=2']));
    assert.strictEqual(s.query('SELECT count(*) AS n FROM games')[0].n, 1);
    assert.deepStrictEqual(s.query('SELECT a FROM ev_probe ORDER BY seq').map(r => r.a), [1, 2]);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM dx_cmd')[0].n, 1);
});

test('a log with two games: each gets its own events, both get the run facts', () => {
    const s = new Store(':memory:', { views: null });
    s.ingest(log(tmp(), 'a.log', [...FACTS, BOT, '[HEV] t=300 ev=probe pid=1 a=1', BOT, '[HEV] t=10 ev=probe pid=1 a=2']));
    const games = s.query('SELECT game_id, game, seed FROM games ORDER BY game');
    assert.deepStrictEqual(games.map(g => [g.game, g.seed]), [[1, 30], [2, 30]]);
    assert.deepStrictEqual(s.query('SELECT a FROM ev_probe WHERE game_id = ?', games[1].game_id).map(r => r.a), [2]);
});

test('field names that differ only in case get their own columns; a failed ingest leaves the store usable', () => {
    const dir = tmp();
    const s = new Store(':memory:', { views: null });
    s.ingest(log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 min=1 Min=2 T=3']));
    assert.deepStrictEqual({ ...s.query('SELECT min, f_Min, f_T, t FROM ev_probe')[0] }, { min: 1, f_Min: 2, f_T: 3, t: 1 });
    // A crash after this log created dx_ and ev_ tables: the rollback undoes them, and the next ingest must not trust the
    // in-memory kinds that still name them.
    const writeGame = s.writeGame;
    s.writeGame = () => { throw new Error('boom'); };
    const bad = log(dir, 'b.log', [...FACTS, BOT, '[HEV] t=1 ev=fresh pid=1 a=1']);
    assert.deepStrictEqual(s.ingestAll([bad]).failed.map(f => f.error), ['boom']);
    s.writeGame = writeGame;
    assert.deepStrictEqual(s.ingestAll([bad]).failed, []);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM ev_fresh')[0].n, 1);
    assert.strictEqual(s.query('SELECT count(*) AS n FROM dx_start')[0].n, 1);
});

test('same content under a new mtime is not re-ingested; manifests name their ok logs; an old store version is rebuilt', () => {
    const dir = tmp();
    const db = path.join(dir, 's.sqlite');
    let s = new Store(db, { views: null });
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    const m = path.join(dir, 'b.manifest');
    fs.writeFileSync(m, `status=ok label="x" seed=30 arm=on lineup=A log="${f}"\nstatus=fail label="y" log="${path.join(dir, 'gone.log')}"\n`);
    assert.strictEqual(s.ingestAll([m]).wrote, 1);
    fs.utimesSync(f, new Date(), new Date(Date.now() + 5000));
    assert.strictEqual(s.ingest(f), false);
    s.db.exec('PRAGMA user_version = 1');
    s.close();
    s = new Store(db, { views: null });
    assert.strictEqual(s.query('PRAGMA user_version')[0].user_version, versionOf(DECLARED));
    assert.strictEqual(s.query('SELECT count(*) AS n FROM logs')[0].n, 0);
    assert.strictEqual(s.ingest(f), true);
});

test('stack view keeps stackCause results when a column also holds text and when why is only ever numeric', () => {
    const s = new Store(':memory:');
    s.ingestAll([log(tmp(), 'a.log', [BOT,
        '[HEV] t=100 ev=stack pid=1 min=1 res=failed why=3',
        '[HEV] t=160 ev=stack pid=1 min=2 res=not_stacked why=x box59=0 bot59=0 vis59=1 after=3',
        '[HEV] t=220 ev=stack pid=1 min=3 res=stacked why=x box59=odd vis59=odd'])]);
    assert.strictEqual(s.colsOf('ev_stack').get('box59'), 'text');
    assert.deepStrictEqual(s.query('SELECT cause FROM stack_attempts ORDER BY t').map(r => r.cause), ['3', 'no-spawn', null]);
});

test('fields named like a row key do not overwrite it', () => {
    const dir = tmp();
    const s = new Store(':memory:', { views: null });
    s.ingest(log(dir, 'a.log', [...FACTS, '10/30 08:01:00 [DOTACTL] t=1 ev=probe log_id=5 seq=9', BOT,
        '[HEV] t=1 ev=probe pid=1 seq=77 game_id=4 a=1', '[HEV] t=2 ev=probe pid=1 a=2']));
    const g = s.query('SELECT game_id FROM games')[0].game_id;
    assert.deepStrictEqual(s.query('SELECT game_id, seq, f_seq, f_game_id FROM ev_probe ORDER BY t').map(r => ({ ...r })),
        [{ game_id: g, seq: 1, f_seq: 77, f_game_id: 4 }, { game_id: g, seq: 2, f_seq: null, f_game_id: null }]);
    const logId = s.query('SELECT log_id FROM logs')[0].log_id;
    assert.deepStrictEqual({ ...s.query('SELECT log_id, f_log_id, f_seq FROM dx_probe')[0] }, { log_id: logId, f_log_id: 5, f_seq: 9 });
    fs.rmSync(path.join(dir, 'a.log'));
    s.prune();
    assert.strictEqual(s.query('SELECT count(*) AS n FROM dx_probe')[0].n, 0);
});

test('a query includes a fragment by name, and names a fragment that does not exist', () => {
    const s = new Store(':memory:');
    const lane = (x, y) => s.query(`WITH pts AS (SELECT 'p' AS kind, 1 AS k, 1 AS seq, 0 AS t, ${x} AS x, ${y} AS y),
-- include: lane_label
z AS (SELECT 1)
SELECT lane FROM lab`)[0].lane;
    assert.deepStrictEqual([lane(-360, -6256), lane(-5920, -5352), lane(-2500, 2500)], ['bot', 'base', 'other']);
    assert.throws(() => s.query('-- include: no_such_fragment\nSELECT 1'), /no fragment no_such_fragment/);
});

test('creep_fate: an enemy deny is named by the other team\'s own_creep_death, each death used once; own denies and losses', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    const D = (t, team, x, y, by, kind = 'melee') => `[HEV] t=${t} ev=creep_death team=${team} kind=${kind} x=${x} y=${y} hp=0.2 by=${by}`;
    const O = (t, team, x, y, by, kind = 'melee') => `[HEV] t=${t} ev=own_creep_death team=${team} kind=${kind} x=${x} y=${y} hp=0.2 by=${by}`;
    s.ingest(log(dir, 'a.log', [BOT,
        D(100, 2, 100, 100, 1),                // team 2 last hit by pid 1
        D(110, 2, 200, 100, 'none'),           // an enemy deny: team 3 denied its own creep 0.2 s later, 50 units away
        O(110.2, 3, 250, 100, 7),
        D(120, 2, 300, 100, 'none'),           // tower or creep kill: nothing denied it
        D(130, 2, 400, 100, 'none'),           // two creeps in one place: the nearer pair wins, the other stays other
        D(130, 2, 600, 100, 'none'),
        O(130.1, 3, 420, 100, 8),
        D(140, 2, 500, 100, 'none', 'ranged'), // a deny of another kind does not pair
        O(140, 3, 500, 100, 9),
        O(150, 2, 0, 0, 1),                    // team 2's own creep denied by pid 1
        O(160, 2, 0, 0, 'none')]));            // and one lost to an enemy last hit or a tower
    const rows = s.query('SELECT t, team, side, kind, fate, pid FROM creep_fate ORDER BY side DESC, t, x').map(r => ({ ...r }));
    const f = (t, side, kind = 'melee') => rows.filter(r => r.t === t && r.side === side && r.kind === kind).map(r => [r.team, r.fate, r.pid]);
    assert.deepStrictEqual(f(100, 'enemy'), [[2, 'own_lh', 1]]);
    assert.deepStrictEqual(f(110, 'enemy'), [[2, 'enemy_deny', 7]]);
    assert.deepStrictEqual(f(120, 'enemy'), [[2, 'other', null]]);
    assert.deepStrictEqual(f(130, 'enemy'), [[2, 'enemy_deny', 8], [2, 'other', null]]);
    assert.deepStrictEqual(f(140, 'enemy', 'ranged'), [[2, 'other', null]]);
    assert.deepStrictEqual(f(150, 'own'), [[2, 'own_deny', 1]]);
    assert.deepStrictEqual(f(160, 'own'), [[2, 'lost', null]]);
    assert.strictEqual(rows.filter(r => r.side === 'own' && r.team === 3).length, 3, 'the other team\'s own deaths are rows too');
});

test('creep_share: taken over (enemy creeps less enemy denies plus own creeps) per team, first 10:00 only', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    const D = (t, team, x, by) => `[HEV] t=${t} ev=creep_death team=${team} kind=melee x=${x} y=100 hp=0.2 by=${by}`;
    const O = (t, team, x, by) => `[HEV] t=${t} ev=own_creep_death team=${team} kind=melee x=${x} y=100 hp=0.2 by=${by}`;
    s.ingest(log(dir, 'a.log', [BOT,
        D(100, 2, 100, 1),     // taken: our last hit
        D(110, 2, 200, 'none'), // an enemy deny (below): out of the denominator
        O(110.2, 3, 250, 7),
        D(120, 2, 300, 'none'), // tower or creep kill: a miss
        O(150, 2, 0, 1),       // taken: our deny of our own creep
        O(160, 2, 0, 'none'),   // lost: a miss
        D(700, 2, 400, 1)]));   // after 10:00: left out
    const r = s.query('SELECT team, taken, den, share FROM creep_share WHERE team = 2')[0];
    assert.deepStrictEqual([r.taken, r.den, r.share], [2, 4, 0.5]);
});

test('creep_fate: by=deny reads enemy_deny, and a log without own_creep_death reads enemy denies as other', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    s.ingest(log(dir, 'a.log', [BOT, '[HEV] t=10 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=deny',
        '[HEV] t=20 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=none']));
    assert.deepStrictEqual(s.query('SELECT t, fate FROM creep_fate ORDER BY t').map(r => [r.t, r.fate]), [[10, 'enemy_deny'], [20, 'other']]);
});
