'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

test('mode hold: seconds per mode, desire value and source, with what the hero did; supports and other windows left out', () => {
    const snap = (t, pid, mode, by, tgt) => line(t, `snap pid=${pid} x=0 y=0 alive=1 mode=${mode} d=0.5 deaths=0${tgt ? ` tgt=${tgt}` : ''} by="${by}"`);
    const lines = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        line(0, 'bot pid=4 hero=h4 team=2 pos=4'),
        // cil3's case: farm mode at OHA's run value with no target, against farm at a farming value hitting a neutral.
        snap(100, 1, 'farm', 'farm 1.10 by raw'),
        snap(101, 1, 'farm', 'farm 1.10 by raw'),
        snap(102, 1, 'farm', 'farm 1.16 by raw+sticky', 'npc_dota_creep_badguys_melee'),
        snap(103, 1, 'farm', 'farm 0.62 by raw', 'npc_dota_neutral_kobold'),
        snap(104, 1, 'laning', 'laning 0.90 by raw', 'npc_dota_creep_badguys_melee'),
        snap(105, 4, 'farm', 'farm 1.10 by raw'),
        snap(700, 1, 'farm', 'farm 1.10 by raw'),
    ];
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-hold-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'mode_hold.sql'), 'utf8');
    const rows = q => s.query(sql, q).map(r => [r.mode, r.desire, r.src, r.secs, r.hero, r.creep, r.neutral, r.idle]);
    assert.deepStrictEqual(rows({ mode: 'farm' }), [
        ['farm', 1.1, 'raw', 2, 0, 0, 0, 2],
        ['farm', 0.62, 'raw', 1, 0, 0, 1, 0],
        ['farm', 1.16, 'raw+sticky', 1, 0, 1, 0, 0],
    ].sort((a, b) => b[3] - a[3] || 0));
    assert.strictEqual(rows({}).length, 4);
    s.db.close();
});
