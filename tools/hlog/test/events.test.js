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
