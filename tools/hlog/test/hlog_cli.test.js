'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { list } = require('../hlog');

const HLOG = path.join(__dirname, '../hlog.js');

test('list: every query and view, each with a first sentence; params read from the SQL and its fragments', () => {
    const rows = list();
    const sql = d => fs.readdirSync(path.join(__dirname, '..', d)).filter(f => f.endsWith('.sql')).length;
    assert.strictEqual(rows.length, sql('queries') + sql('views'));
    for (const r of rows) assert.ok(r.about.length > 10, `${r.name} has no header sentence`);
    const at = rows.find(r => r.name === '@hero_at');
    for (const p of ['like', 'game', 'pid', 'hero', 't']) assert.ok(at.params.split(' ').includes(p), `@hero_at ${p}`);
    assert.ok(rows.find(r => r.name === '@core_deaths').params.split(' ').includes('until'), 'a param from an included fragment');
    assert.ok(list('hero_at').every(r => /hero_at/.test(r.name + r.about)));
});

test('q on a store with no logs says so', () => {
    const db = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cli-')), 's.sqlite');
    const r = spawnSync(process.execPath, [HLOG, 'q', 'SELECT 1 AS one', '--db', db, '--no-ingest'], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stderr, /has no logs/);
    assert.match(r.stdout, /one/);
});

test('events: one hero in a window, oldest first, noisy lines left out, a short snapshot', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ev-'));
    const log = path.join(dir, '2026-11-13T00-00-00-probe_A_on_1.log');
    fs.writeFileSync(log, [
        '[HEV] t=1 ev=bot pid=0 hero=luna team=2 pos=1',
        '[HEV] t=1 ev=bot pid=1 hero=pudge team=2 pos=3',
        '[HEV] t=10 ev=snap pid=0 hp=90 mode=laning x=1 y=2 gold=5',
        '[HEV] t=10.5 ev=lane_pos pid=0 d=3',
        '[HEV] t=11 ev=mode pid=0 from=laning to=retreat',
        '[HEV] t=11 ev=mode pid=1 from=laning to=attack',
        '[HEV] t=30 ev=mode pid=0 from=retreat to=laning',
    ].join('\n') + '\n');
    const db = path.join(dir, 's.sqlite');
    const r = spawnSync(process.execPath, [HLOG, 'events', log, '--hero', 'luna', '--from', '0:05', '--to', '20', '--db', db], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    const lines = r.stdout.trim().split('\n');
    assert.strictEqual(lines.length, 2, r.stdout);
    assert.match(lines[0], /^t=10 snap /);
    assert.ok(!/gold/.test(lines[0]), 'a short snapshot');
    assert.match(lines[1], /^t=11 mode .*to=retreat/);
    const d = spawnSync(process.execPath, [HLOG, 'digest', log, '--db', db], { encoding: 'utf8' });
    assert.match(d.stdout, /pids: 0=luna\(rad pos1\) 1=pudge\(rad pos3\)/);
    assert.match(d.stdout, /label: probe_A_on_1/);
});

test('q: a like or file param naming a run label resolves to that log', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-label-'));
    const log = path.join(dir, '2026-11-13T00-00-00-probe_B_on_1.log');
    fs.writeFileSync(log, '[HEV] t=1 ev=bot pid=0 hero=luna team=2 pos=1\n');
    const db = path.join(dir, 's.sqlite');
    const q = p => spawnSync(process.execPath, [HLOG, 'q', 'SELECT count(*) AS n FROM games WHERE file LIKE :like', '--p', p, '--db', db, '--logs', dir, '--json'], { encoding: 'utf8' });
    const r = q('like=%probe_B_on_1%');
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /"n": ?1/);
    const byLabel = q('like=probe_B_on_1');
    assert.match(byLabel.stderr, /is a label: using/);
    assert.match(byLabel.stdout, /"n": ?1/);
});
