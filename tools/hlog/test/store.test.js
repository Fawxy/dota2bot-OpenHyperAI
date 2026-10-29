'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

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
    // A later log with a non-numeric value turns the column to text, including the rows already stored.
    s.ingest(log(dir, 'b.log', [BOT, '[HEV] t=3 ev=probe pid=1 a=x7']));
    assert.strictEqual(s.colsOf('ev_probe').get('a'), 'text');
    assert.deepStrictEqual(s.query('SELECT a, typeof(a) AS k FROM ev_probe ORDER BY t').map(r => [r.a, r.k]),
        [['1', 'text'], ['2', 'text'], ['x7', 'text']]);
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
