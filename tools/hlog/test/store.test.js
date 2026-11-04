'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store, INGEST_VERSION, DECLARED, versionOf, storeFile, STALE_MS } = require('../store');

const { jobEnds, runeJobs, lanePartnerLvl10 } = require('../dynamic');
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

test('stores of two versions keep their own files: opening one never empties the other', () => {
    const dir = tmp();
    const kindsA = { ev_probe: { a: 'num' } };
    const kindsB = { ev_probe: { a: 'text' } };
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    let a = new Store(storeFile(versionOf(kindsA), dir), { views: null, kinds: kindsA });
    a.ingest(f);
    a.close();
    const b = new Store(storeFile(versionOf(kindsB), dir), { views: null, kinds: kindsB });
    b.ingest(f);
    b.close();
    a = new Store(storeFile(versionOf(kindsA), dir), { views: null, kinds: kindsA });
    assert.strictEqual(a.ingest(f), false);
    assert.deepStrictEqual(a.query('SELECT a, typeof(a) AS k FROM ev_probe').map(r => [r.a, r.k]), [[1, 'integer']]);
});

test('two processes on one store: a log the other ingested while this one waited for the lock is not written twice', () => {
    const dir = tmp();
    const db = storeFile(versionOf(DECLARED), dir);
    const a = new Store(db, { views: null });
    const b = new Store(db, { views: null });
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    // b has checked the log and found it new; a takes the lock first and ingests it.
    const exec = b.db.exec.bind(b.db);
    b.db.exec = sql => {
        if (sql === 'BEGIN IMMEDIATE') { b.db.exec = exec; a.ingest(f); }
        return exec(sql);
    };
    assert.strictEqual(b.ingest(f), false);
    assert.strictEqual(b.query('SELECT count(*) AS n FROM logs')[0].n, 1);
    assert.strictEqual(b.query('SELECT count(*) AS n FROM ev_probe')[0].n, 1);
});

test('two processes on one store: tables and columns the other added are known before this one writes', () => {
    const dir = tmp();
    const db = storeFile(versionOf(DECLARED), dir);
    const a = new Store(db, { views: null });
    const b = new Store(db, { views: null });
    a.ingest(log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']));
    b.ingest(log(dir, 'b.log', [BOT, '[HEV] t=2 ev=probe pid=1 a=2 extra=3']));
    assert.deepStrictEqual(b.query('SELECT a, extra FROM ev_probe ORDER BY t').map(r => [r.a, r.extra]), [[1, null], [2, 3]]);
});

test('two processes open a new store at once: the second does not empty what the first built meanwhile', () => {
    const { DatabaseSync } = require('node:sqlite');
    const dir = tmp();
    const db = storeFile(versionOf(DECLARED), dir);
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    const exec = DatabaseSync.prototype.exec;
    let raced = false;
    // b has read the new file's version as unset; a builds the store and ingests before b takes the lock.
    DatabaseSync.prototype.exec = function (sql) {
        if (sql === 'BEGIN IMMEDIATE' && !raced) {
            raced = true;
            const a = new Store(db, { views: null });
            a.ingest(f);
            a.close();
        }
        return exec.call(this, sql);
    };
    let b;
    try { b = new Store(db, { views: null }); } finally { DatabaseSync.prototype.exec = exec; }
    assert.strictEqual(b.query('SELECT count(*) AS n FROM ev_probe')[0].n, 1);
});

test('two processes on one store: views open on tables the other wrote while this one ingested nothing', () => {
    const dir = tmp();
    const views = path.join(dir, 'views');
    fs.mkdirSync(views);
    fs.writeFileSync(path.join(views, 'probe_x.sql'), '-- needs: ev_probe(x)\nSELECT game_id, a, x FROM ev_probe\n');
    const db = storeFile(versionOf(DECLARED), dir);
    const a = new Store(db, { views });
    const b = new Store(db, { views });
    const f = log(dir, 'a.log', [BOT, '[HEV] t=1 ev=probe pid=1 a=1']);
    a.ingestAll([f]);
    assert.strictEqual(b.ingestAll([f]).wrote, 0);
    assert.deepStrictEqual(b.query('SELECT a, x FROM probe_x').map(r => [r.a, r.x]), [[1, null]]);
});

test('opening a version store deletes other version stores unopened for a week, and nothing else', () => {
    const dir = tmp();
    const old = Date.now() / 1000 - STALE_MS / 1000 - 3600;
    const make = (name, mtime) => {
        const p = path.join(dir, name);
        fs.writeFileSync(p, '');
        if (mtime) fs.utimesSync(p, mtime, mtime);
        return p;
    };
    const stale = make('hlog-1.sqlite', old);
    const staleWal = make('hlog-1.sqlite-wal', old);
    const fresh = make('hlog-2.sqlite');
    const other = make('hlog.sqlite', old);
    new Store(storeFile(versionOf(DECLARED), dir), { views: null }).close();
    assert.deepStrictEqual([stale, staleWal, fresh, other].map(p => fs.existsSync(p)), [false, false, true, true]);
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

test('job_ends sorts what ended each job', () => {
    const s = new Store(':memory:');
    const f = log(tmp(), 'j.log', ['[HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456', '[HEV] t=-60 ev=bot pid=2 hero=muerta team=2',
        '[HEV] t=99 ev=job pid=1 job=stack phase=start why=trigger host=17',
        '[HEV] t=100 ev=job pid=1 job=stack phase=end why=preempted:mode=7 host=17 hit=0',
        '[HEV] t=110 ev=job pid=1 job=stack phase=end why=preempted:mode=2 host=17 hit=1',
        '[HEV] t=120 ev=job pid=2 job=stack phase=end why=preempted:mode=2 host=17 hit=0',
        '[HEV] t=130 ev=job pid=1 job=stack phase=end why=cancelled:retreat host=17 hit=1',
        '[HEV] t=140 ev=job pid=1 job=stack phase=end why=cancelled:run host=17 hit=0',
        '[HEV] t=150 ev=job pid=1 job=stack phase=end why=ok host=17 hit=0']);
    s.ingestAll([f]);
    assert.deepStrictEqual(s.query('SELECT why, class, hit FROM job_ends ORDER BY t').map(r => [r.why, r.class, r.hit]), [
        ['preempted:mode=7', 'oha-gated', 0], ['preempted:mode=2', 'valve', 1], ['preempted:mode=2', 'exception', 0],
        ['cancelled:retreat', 'exception', 1], ['cancelled:run', 'oha-gated', 0], ['ok', 'other', 0]]);
    const file = s.query('SELECT file FROM games')[0].file;
    assert.strictEqual(jobEnds(s, file, 1).filter(j => j.class === 'oha-gated').length, 2);
    assert.deepStrictEqual(jobEnds(new Store(':memory:'), file, 1), []);
});

test('rune_jobs counts started trips, on time by spawn + 2, and deaths on a trip', () => {
    const s = new Store(':memory:');
    const f = log(tmp(), 'r.log', ['[HEV] t=-60 ev=bot pid=4 hero=lion team=2 pos=4 schema=2 build=0123456', '[HEV] t=-60 ev=bot pid=3 hero=axe team=2 pos=3',
        '[HEV] t=361 ev=rune_job pid=4 pos=4 kind=power spawn=360 res=fail why=no_target:rune label=pickup side=top left=340 arr=355 away=21 died=0 hit=0',
        '[HEV] t=365 ev=rune_job pid=5 pos=5 kind=power spawn=360 res=skip why=stack',
        '[HEV] t=365 ev=rune_job pid=5 pos=5 kind=power spawn=360 res=fail why=preempted:mode=4 label=travel left=340 away=2 died=0 hit=0',
        '[HEV] t=366 ev=rune_job pid=4 pos=4 kind=wisdom spawn=420 res=fail why=timeout:late label=travel left=400 away=26 died=1 hit=1',
        '[HEV] t=424 ev=rune_job pid=4 pos=4 kind=wisdom spawn=420 res=ok why=ok label=channel left=400 arr=422 away=24 died=0 hit=0',
        '[HEV] t=600 ev=snap pid=3 human=0 lvl=6', '[HEV] t=600 ev=snap pid=4 human=0 lvl=5']);
    s.ingestAll([f]);
    const file = s.query('SELECT file FROM games')[0].file;
    const rows = runeJobs(s, file, 1);
    assert.deepStrictEqual(rows.map(r => [r.kind, r.started, r.interrupted, r.on_time, r.died]), [
        ['power', 1, 0, 1, 0], ['power', 0, 0, 0, 0], ['power', 1, 1, 0, 0], ['wisdom', 1, 0, 0, 1], ['wisdom', 1, 0, 1, 0]]);
    assert.strictEqual(lanePartnerLvl10(s, file, 1), 6);
    assert.deepStrictEqual(runeJobs(new Store(':memory:'), file, 1), []);
});

test('pull_attempts: diverted at div 0.75, split short of the whole wave (3 of 4 counts) and whole at 1, the kind (full before slice pull-half), the start choice by slot, the lane eq 30 and 60 s after from the puller team', () => {
    const s = new Store(':memory:');
    const f = log(tmp(), 'p.log', ['[HEV] t=-60 ev=bot pid=5 hero=lion team=2 pos=5 schema=2 build=0123456', '[HEV] t=-60 ev=bot pid=9 hero=lich team=3 pos=5',
        '[HEV] t=74 ev=choice pid=5 kind=pull go=1 want=1 src=own lane=3 slot=78.5 st=OUT q=0.7 mv=640 cf=-420 tw=0 ms=3.1',
        '[HEV] t=78 ev=lane_read team=2 lane=3 eq=0.2', '[HEV] t=79 ev=lane_read team=2 lane=3 eq=0.3', '[HEV] t=79 ev=lane_read team=3 lane=3 eq=-0.3',
        '[HEV] t=88 ev=pull_job pid=5 pos=5 lane=3 camp=1 slot=78.5 res=ok why=ok label=watch div=0.75 n=4 left=74 away=14 died=0 hit=0',
        '[HEV] t=104 ev=choice pid=5 kind=pull go=0 want=1 why=hit src=own lane=3 slot=108.5 st=OUT',
        '[HEV] t=109 ev=lane_read team=2 lane=3 eq=-0.2', '[HEV] t=139 ev=lane_read team=2 lane=3 eq=-0.5',
        '[HEV] t=140 ev=choice pid=9 kind=pull go=1 want=1 src=own lane=3 slot=138.5 st=HOLD q=0.6',
        '[HEV] t=150 ev=pull_job pid=9 pos=5 lane=3 camp=7 slot=138.5 pk=half res=fail why=timeout:late label=travel div=0.5 n=4 left=130 away=20 died=1 hit=1',
        '[HEV] t=180 ev=pull_job pid=9 pos=5 lane=3 camp=7 slot=168.5 pk=half res=ok why=ok label=watch div=1 n=4 left=160 away=20 died=0 hit=0 dt=1']);
    s.ingestAll([f]);
    const rows = s.query('SELECT pid, pk, diverted, split, whole, died, st, cf, eq0, d30, d60 FROM pull_attempts ORDER BY t');
    assert.deepStrictEqual(rows.map(r => [r.pid, r.pk, r.diverted, r.split, r.whole, r.died, r.st, r.cf]),
        [[5, 'full', 1, 1, 0, 0, 'OUT', -420], [9, 'half', 0, 1, 0, 1, 'HOLD', null], [9, 'half', 1, 0, 1, 0, undefined, undefined]].map(r => r.map(x => x === undefined ? null : x)));
    // Radiant's row at the slot (0.3 at t=79, not Dire's -0.3), then -0.2 at +30 and -0.5 at +60.
    assert.deepStrictEqual([rows[0].eq0, Math.round(rows[0].d30 * 10) / 10, Math.round(rows[0].d60 * 10) / 10], [0.3, -0.5, -0.8]);
    assert.strictEqual(rows[1].eq0, null);
});

test('pull_watch_cases: the arrival sample names why an ok pull was not diverted', () => {
    const s = new Store(':memory:');
    const W = (t, slot, f) => `[HEV] t=${t} ev=pull_watch pid=5 slot=${slot} ph=watch ${f}`;
    const J = (t, slot, div) => `[HEV] t=${t} ev=pull_job pid=5 pos=5 lane=3 camp=1 slot=${slot} res=ok why=ok label=watch div=${div} n=4 left=${slot - 10} away=14 died=0 hit=0 dt=${div}`;
    const f = log(tmp(), 'w.log', ['[HEV] t=-60 ev=bot pid=5 hero=lion team=2 pos=5 schema=2 build=0123456',
        '[HEV] t=95 ev=choice pid=5 kind=pull go=1 want=1 src=own lane=3 slot=100 st=OUT',
        // 100: the wave arrives at 108 with the kobolds back at camp, 900 from it; the earlier sample (wave 600 away) is not the arrival.
        W(106, 100, 'wc=0 won=0 wd=600 nn=2 ntc=0 nd=300 nh=500 nt=p'), W(108, 100, 'wc=4 won=0 wd=200 nn=0 ntc=0 nd=900 nh=100 nt=x'), J(115, 100, 0),
        // 200: neutrals 300 from our creeps at arrival and none of ours on them; 300: two of four fought; 400: diverted.
        W(208, 200, 'wc=4 won=0 wd=100 nn=3 ntc=0 nd=300 nh=900 nt=p'), J(215, 200, 0),
        W(308, 300, 'wc=4 won=2 wd=100 nn=3 ntc=1 nd=200 nh=900 nt=c'), J(315, 300, 0.5),
        W(408, 400, 'wc=4 won=4 wd=100 nn=3 ntc=1 nd=100 nh=900 nt=c'), J(415, 400, 1),
        // 500: the wave never came within 300 of the meet point.
        W(508, 500, 'wc=0 won=0 wd=700 nn=3 nd=700 nh=900 nt=p'), J(515, 500, 0)]);
    s.ingestAll([f]);
    const rows = s.query('SELECT slot, cause, a_nd, arr_after FROM pull_watch_cases ORDER BY slot');
    assert.deepStrictEqual(rows.map(r => [r.slot, r.cause]), [[100, 'home'], [200, 'near-no-fight'], [300, 'partial'], [400, 'diverted'], [500, 'no-wave']]);
    assert.deepStrictEqual([rows[0].a_nd, rows[0].arr_after], [900, 8]);
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

test('creep_guard: team and core last hits, denies and deaths at 10:00, and the rises with no logged death', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    const B = (pid, team, pos) => `[HEV] t=-60 ev=bot pid=${pid} hero=h${pid} team=${team} pos=${pos}`;
    const S = (t, pid, lh, dn, deaths) => `[HEV] t=${t} ev=snap pid=${pid} x=0 y=0 alive=1 hp=100 mp=100 lvl=1 lh=${lh} dn=${dn} kills=0 deaths=${deaths}`;
    // pid 7 is a Radiant bot and pid 5 a Dire one (team comes from ev=bot, not the pid); pid 9 is a human with no pos
    s.ingest(log(dir, 'a.log', [B(0, 2, 1), B(7, 2, 5), B(5, 3, 1), B(6, 3, 2), '[HEV] t=-60 ev=player pid=9 hero=abaddon team=3',
        S(100, 0, 5, 1, 0), S(100, 6, 1, 1, 0),
        `[HEV] t=200 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=0`,
        `[HEV] t=300 ev=own_creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=0`,
        S(590, 0, 10, 2, 1), S(590, 7, 3, 4, 2), S(590, 5, 7, 0, 0), S(590, 9, 2, 2, 0),
        S(598, 6, 4, 3, 1),   // seen at 598: no extra death
        S(700, 0, 99, 99, 9)]));
    s.refreshViews();
    const r = s.query('SELECT * FROM creep_guard WHERE team = 2')[0];
    assert.deepStrictEqual([r.team_lh, r.team_dn, r.core_lh, r.core_dn, r.deaths, r.not_in_share], [13, 6, 10, 2, 3 + 2, 17]);
    // the pos 5 (pid 7) is the support split; the pos 1 is not in it
    assert.deepStrictEqual([r.sup_lh, r.sup_dn], [3, 4]);
    // pids 0 and 7 last seen at 590 (over 2.5 s before 10:00, game ran on): each still dead, +1 each
    const d = s.query('SELECT * FROM creep_guard WHERE team = 3')[0];
    assert.deepStrictEqual([d.team_lh, d.team_dn, d.core_lh, d.deaths, d.not_in_share], [13, 5, 11, 3, null], 'dire: human in the team columns only; pids 5 and 9 still dead at 10:00, pid 6 seen at 598; no share row');
    assert.deepStrictEqual([d.sup_lh, d.sup_dn], [0, 0], 'dire: no lineup support, and the human is not counted as one');
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

test('lane_activity and @lane_time: activity per snap, choice against option, presence and conversion', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    const B = (pid, team, pos) => `[HEV] t=-60 ev=bot pid=${pid} hero=h${pid} team=${team} pos=${pos}`;
    const S = (t, o) => `[HEV] t=${t} ev=snap pid=${o.pid ?? 0} x=0 y=0 alive=${o.alive ?? 1} hp=${o.hp ?? 100} mode=${o.mode ?? 'laning'} d=${o.d ?? 0.45}` +
        (o.tgt ? ` tgt=${o.tgt}` : '') + (o.ol !== undefined ? ` ol=${o.ol} od=0 ar=500` : '') + (o.ed ? ` ed=${o.ed}` : '') + (o.hit ? ' hit=1' : '');
    const CREEP = 'npc_dota_creep_badguys_melee', HERO = 'npc_dota_hero_lion';
    const f = log(dir, 'a.log', [B(0, 2, 1), B(5, 3, 4),
        S(50, { ol: 1 }),                                    // before `from`
        S(100, { tgt: HERO, ol: 0, ed: 400 }),               // in range, nothing to take, trading
        S(101, { ol: 0, ed: 500, hit: 1 }),                  // in range and hit, no reply
        S(102, { tgt: CREEP, ol: 1, d: 0.9 }),               // a last hit on offer, taken; at the spike
        S(103, { ol: 2, hp: 30 }),                           // a last hit on offer, standing; low HP in laning
        S(104, { mode: 'retreat', ol: 0, ed: 900 }),         // enemy out of range
        S(105, { mode: 'retreat', tgt: HERO, ol: 0 }),       // a target outranks the mode
        S(106, { mode: 'farm', tgt: 'npc_dota_neutral_kobold', ol: 0 }),
        S(107, { mode: 'rune', ol: 0 }),
        S(108, { tgt: 'npc_dota_goodguys_tower1_bot', ol: 0 }),
        S(109, { pid: 5, ol: 0 }),
        '[HEV] t=200 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=0 p1d=300',
        '[HEV] t=201 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=none p1d=900',
        '[HEV] t=202 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=none p1d=1100',
        '[HEV] t=610 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=0 p1d=100',
        S(650, { ol: 1 })]);   // after `until`
    s.ingest(f);
    s.refreshViews();
    const acts = s.query('SELECT t, activity, spike, in_range FROM lane_activity WHERE pid = 0 AND t BETWEEN 100 AND 108 ORDER BY t').map(r => [r.activity, r.spike, r.in_range]);
    assert.deepStrictEqual(acts, [['hero', 0, 1], ['lane', 0, 1], ['creep', 1, 0], ['lane', 0, 0], ['retreat', 0, 0], ['hero', 0, 0], ['neutral', 0, 0], ['other', 0, 0], ['building', 0, 0]]);
    const sql = fs.readFileSync(path.join(__dirname, '../queries/lane_time.sql'), 'utf8');
    const r = s.query(sql, {}).find(x => x.pid === 0);
    assert.deepStrictEqual([r.secs, r.hero, r.creep, r.retreat, r.lane, r.other, r.low_lane, r.spike], [9, 2, 1, 1, 2, 3, 1, 1]);
    assert.deepStrictEqual([r.lh_open, r.lh_open_creep, r.trade_open, r.trade_open_hero, r.hit_noreply], [2, 1, 2, 1, 1]);
    assert.deepStrictEqual([r.near, r.taken], [2, 1]);
    const sup = s.query(sql, {}).find(x => x.pid === 5);
    assert.deepStrictEqual([sup.secs, sup.near, sup.taken], [1, null, null], 'a support has no creep_death distances');
});

test('@lane_time: a build without the option fields reads NULL, not 0', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    s.ingest(log(dir, 'old.log', ['[HEV] t=-60 ev=bot pid=0 hero=h team=2 pos=1',
        '[HEV] t=100 ev=snap pid=0 x=0 y=0 alive=1 hp=100 mode=laning d=0.4', '[HEV] t=601 ev=snap pid=0 x=0 y=0 alive=1 hp=100 mode=laning d=0.4']));
    s.refreshViews();
    const r = s.query(fs.readFileSync(path.join(__dirname, '../queries/lane_time.sql'), 'utf8'), {})[0];
    assert.deepStrictEqual([r.secs, r.lane, r.lh_open, r.trade_open, r.hit_noreply], [1, 1, null, null, null]);
});

test('@lane_time: near and taken obey from; a siege creep target is a creep', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    s.ingest(log(dir, 'a.log', ['[HEV] t=-60 ev=bot pid=0 hero=h team=2 pos=1',
        '[HEV] t=50 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=0 p1d=100',
        '[HEV] t=100 ev=snap pid=0 x=0 y=0 alive=1 hp=100 mode=laning d=0.4 tgt=npc_dota_badguys_siege',
        '[HEV] t=120 ev=creep_death team=2 kind=melee x=1 y=1 hp=0.2 by=none p1d=100',
        '[HEV] t=601 ev=snap pid=0 x=0 y=0 alive=1 hp=100 mode=laning d=0.4']));
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '../queries/lane_time.sql'), 'utf8');
    const r = s.query(sql, {})[0];
    assert.deepStrictEqual([r.creep, r.lane, r.near, r.taken], [1, 0, 1, 0], 'from 90: the death at 50 is out');
    const all = s.query(sql, { from: 0 })[0];
    assert.deepStrictEqual([all.near, all.taken], [2, 1]);
});

test('lane_read_check and @lane_read_check: the reading against the other team\'s census and ev=snap', () => {
    const dir = tmp();
    const s = new Store(':memory:');
    const L = (t, team, o) => `[HEV] t=${t} ev=lane_read team=${team} lane=3 adv=${o.adv} eq=${o.eq} a=3 e=${o.e} ap=${o.ap} ep=500` +
        ` of=0.5 ef=0.5 ot=${o.ot} et=${o.et} cyc=${t % 30} cn=${o.cn} chp=${o.chp} cpw=${o.chp} cl=${o.cl} cnn=${o.cnn} cnp=${o.cnp}` +
        ` clx=${o.clx} cly=-5000 fx=${o.fx} fy=-5000 dead=0` + (o.ee ? ` ee=${o.ee}` : '');
    // Fronts meet at x = 100; the lead creeps at x = 700 and -300 meet at 200. Amounts differ by frame and are not used.
    const rad = { adv: 1.3, eq: 0.4, e: 2, ap: 1000, ot: 0.3, et: 0.7, cn: 4, cl: 0.55, clx: 700, fx: 0, cnn: 3, cnp: 900 };
    const dire = { adv: 0.9, eq: -0.2, e: 3, ap: 1200, ot: 0.55, et: 0.15, cn: 3, cl: 0.35, clx: -300, fx: 200, cnn: 3, cnp: 1500 };
    s.ingest(log(dir, 'a.log', [
        '[HEV] t=-60 ev=bot pid=0 hero=h0 team=2 pos=1',
        L(100.2, 2, { ...rad, chp: 2000, ee: '7:12:1500;8:v:300:50:3;9:40:5000' }),
        L(100.4, 2, { ...rad, chp: 9999 }),                                  // second line in the same second: the first counts
        L(100.6, 3, { ...dire, chp: 1500 }),
        L(110.1, 2, { ...rad, chp: 1800 }),
        L(110.3, 3, { ...dire, chp: 1000 }),
        '[HEV] t=100.5 ev=snap pid=7 x=1000 y=-5000 alive=1 hp=80',          // missing, truly 1,000 from the front
        '[HEV] t=100.5 ev=snap pid=9 x=-1500 y=-5000 alive=1 hp=80',         // missing, read 5,000 away, truly 1,500
    ]));
    s.refreshViews();
    const r = s.query('SELECT * FROM lane_read_check WHERE team = 2 AND sec = 100')[0];
    assert.ok(Math.abs(r.adv_true - (1 + (1000 - 1500) / (1000 + 1500 + 550))) < 1e-9, 'enemy creeps counted by their own census');
    assert.deepStrictEqual([r.e_seen, r.e_true], [2, 3]);
    assert.strictEqual(r.meet_err, 100, 'fronts meet at 100, the lead creeps at 200');
    assert.deepStrictEqual([r.hp_lost, r.ehp_lost], [200, 500]);
    const q = s.query(fs.readFileSync(path.join(__dirname, '../queries/lane_read_check.sql'), 'utf8'), {})[0];
    assert.deepStrictEqual([q.n1, q.n2, q.meet_mean, q.meet_500, q.n3, q.agree3, q.fogged], [4, 4, 100, 1, 1, 1, 0.5],
        'dire\'s 0.9 is within 0.2 of even');
    assert.deepStrictEqual([q.n4, q.near4, q.recall4, q.precision4], [2, 2, 0.5, 1]);
});

test('a declared column exists before any line carries it', () => {
    const dir = tmp();
    const s = new Store(':memory:', { views: null, kinds: { ev_play: { kind: 'text', zero: 'text' } } });
    s.ingest(log(dir, 'a.log', [BOT, '10/30 08:00:02 [HEV] t=360 ev=play pid=1 kind=gank w=0.3 fire=1']));
    assert.deepStrictEqual(s.db.prepare('SELECT kind, zero FROM ev_play').all().map(r => ({ ...r })), [{ kind: 'gank', zero: null }]);
});
