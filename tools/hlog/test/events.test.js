'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { Store } = require('../store');
const { load, build, tableName, STORE_KIND } = require('../gen_events');

const GEN = path.join(__dirname, '../gen_events.js');

test('EVENTS.md and events.json are fresh against events.ts', () => {
    const r = spawnSync(process.execPath, [GEN, '--check'], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
});

test('declaration: known types only, unique tables, no key that collides with a row column', () => {
    const events = load();
    const tables = new Map();
    for (const [ev, fields] of Object.entries(events)) {
        assert.ok(/^[a-z][a-z0-9_]*$/.test(ev), `event name ${ev}`);
        const t = tableName(ev);
        assert.ok(!tables.has(t), `${ev} and ${tables.get(t)} share table ${t}`);
        tables.set(t, ev);
        for (const [f, type] of Object.entries(fields)) {
            assert.ok(STORE_KIND[type], `${ev}.${f}: type ${type}`);
            assert.ok(!['game_id', 'seq', 't', 'log_id'].includes(f), `${ev}.${f} is a row column`);
        }
    }
    assert.ok(Object.keys(events).length >= 76);
});

test('build: only str is forced to text; the rest are inferred', () => {
    const { json } = build({ probe: { a: 'num', b: 'bool', c: 'str', d: 'mixed', e: 'numstr' } });
    assert.deepStrictEqual(JSON.parse(json).kinds, { ev_probe: { c: 'text' } });
});

test('store: a declared text field stays text when every logged value looks numeric', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-events-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, [
        '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456',
        '[HEV] t=1 ev=cmd by=2 team=2 name=defend args=1 text=5',
    ].join('\n') + '\n');
    const s = new Store(':memory:', { views: null });
    s.ingest(f);
    assert.strictEqual(s.colsOf('ev_cmd').get('text'), 'text');
    assert.strictEqual(s.colsOf('ev_cmd').get('team'), 'num');
});

test('store: numbers printed from a mixed field stay INTEGER rows (creep_death.by, lane_enemy_role.members)', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-events-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, [
        '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456',
        '[HEV] t=1 ev=creep_death team=2 kind=melee x=1 y=2 hp=0.1 by=3',
        '[HEV] t=2 ev=creep_death team=2 kind=melee x=1 y=2 hp=0.1 by=deny',
    ].join('\n') + '\n');
    const s = new Store(':memory:', { views: null });
    s.ingest(f);
    assert.deepStrictEqual(s.query("SELECT count(*) AS n FROM ev_creep_death WHERE by = 3").map(r => Number(r.n)), [1]);
    assert.strictEqual(s.query('SELECT typeof(by) AS k FROM ev_creep_death ORDER BY t')[0].k, 'integer');
});

test('store: a changed declaration rebuilds the store, an unchanged one keeps it', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-events-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, ['10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456', '[HEV] t=1 ev=probe pid=1 a=5'].join('\n') + '\n');
    const db = path.join(dir, 'h.sqlite');
    let s = new Store(db, { views: null, kinds: { ev_probe: { a: 'text' } } });
    s.ingest(f);
    s.db.close();
    s = new Store(db, { views: null, kinds: { ev_probe: { a: 'text' } } });
    assert.strictEqual(Number(s.query('SELECT count(*) AS n FROM ev_probe')[0].n), 1);
    s.db.close();
    s = new Store(db, { views: null, kinds: {} });
    assert.strictEqual(s.tables().includes('ev_probe'), false);
    s.db.close();
});

test('stack_attempts view: left59 is pid:distance of the heroes still in the box, death_flag is 0 when death is absent', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-events-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, [
        '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456',
        '[HEV] t=1 ev=stack pid=1 min=2 res=not_stacked box59=0 vis59=1 n59=3:900:in:150,4:20:out:700,5:1:in:9 death=1',
        '[HEV] t=2 ev=stack pid=1 min=3 res=not_stacked box59=0 vis59=1 n59=4:20:out:700',
        '[HEV] t=3 ev=stack pid=1 min=4 res=skip',
    ].join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const rows = s.query('SELECT left59, death_flag, death FROM stack_attempts ORDER BY t').map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => r.left59), ['3:150,5:9', '-', null]);
    assert.deepStrictEqual(rows.map(r => Number(r.death_flag)), [1, 0, 0]);
    assert.strictEqual(rows[2].death, null);
});

test('convenience views: hero_minute, lua_errors, mode_time, creep_kills', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-views-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, [
        '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456',
        '[HEV] t=10 ev=snap pid=1 lh=1 dn=0 kills=0 deaths=0 gold=700 lvl=1 hp=100 alive=1',
        '[HEV] t=59 ev=snap pid=1 lh=2 dn=0 kills=0 deaths=0 gold=720 lvl=2 hp=90 alive=1',
        '[HEV] t=61 ev=snap pid=1 lh=3 dn=1 kills=0 deaths=1 gold=800 lvl=2 hp=50 alive=1',
        '[HEV] t=5 ev=lua_error pid=1 where=Foo.Bar n=1 msg=x',
        '[HEV] t=9 ev=lua_error pid=1 where=Foo.Bar n=4 msg=x',
        '[HEV] t=20 ev=mode pid=1 from=laning to=farm d=0.4 dwell=12',
        '[HEV] t=50 ev=mode pid=1 from=farm to=laning d=0.4 dwell=30',
        '[HEV] t=60 ev=mode pid=1 from=laning to=farm d=0.4 dwell=10',
        '[HEV] t=15 ev=creep_death team=3 kind=melee x=1 y=2 hp=0.1 by=1',
        '[HEV] t=16 ev=creep_death team=3 kind=melee x=1 y=2 hp=0.1 by=1',
        '[HEV] t=17 ev=creep_death team=3 kind=melee x=1 y=2 hp=0.1 by=deny',
    ].join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const rows = sql => s.query(sql).map(r => ({ ...r }));
    assert.deepStrictEqual(rows('SELECT minute, t, lh, deaths FROM hero_minute ORDER BY minute').map(r => [r.minute, r.t, r.lh, r.deaths]),
        [[0, 59, 2, 0], [1, 61, 3, 1]]);
    assert.deepStrictEqual(rows('SELECT site, lines, max_n FROM lua_errors').map(r => [r.site, Number(r.lines), Number(r.max_n)]), [['Foo.Bar', 2, 4]]);
    assert.deepStrictEqual(rows('SELECT mode, secs, stints FROM mode_time ORDER BY mode').map(r => [r.mode, Number(r.secs), Number(r.stints)]),
        [['farm', 30, 1], ['laning', 22, 2]]);
    assert.deepStrictEqual(rows('SELECT killer, n FROM creep_kills ORDER BY killer').map(r => [String(r.killer), Number(r.n)]), [['1', 2], ['deny', 1]]);
});
