'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

// Slice chase-log: the view @chase (queries/chase.sql).
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const query = fs.readFileSync(path.join(__dirname, '..', 'queries', 'chase.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-chase-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(query, {}).map(r => [r.t, r.pid, r.side, r.pos, r.nsp, r.end_ph, r.end_dt, r.end_d, r.end_thp]);
    s.db.close();
    return out;
}

const bots = [line(0, 'bot pid=1 hero=h1 team=2 pos=1 ours=Threat:1'), line(0, 'bot pid=6 hero=h6 team=3 pos=3 ours=Threat:0')];
const lost = (t, pid, sp) => line(t, `chase pid=${pid} ph=lost role=core ek=kill tgt=7 hp=0.8 thp=0.3 kh=0.4 d=700 gap=150 ms=310 tms=300` +
    (sp ? ` sp="${sp}"` : ''));

test('chase: a loss pairs with the watch end that follows it, per hero; spells counted', () => {
    const rows = run([...bots,
        lost(100, 1, 'a,600,0.3,8,90;b,700,0.5,16,120'),
        lost(101, 6),
        line(103, 'chase pid=1 ph=seen ek=kill tgt=7 dt=3 alive=1 d=420 thp=0.35 hp=0.8 mode=2'),
        line(113, 'chase pid=6 ph=gone ek=kill tgt=7 dt=12 alive=1 hp=0.9 mode=1'),
    ]);
    assert.deepStrictEqual(rows, [
        [100, 1, 'ours', 1, 2, 'seen', 3, 420, 0.35],
        [101, 6, 'oha', 3, 0, 'gone', 12, null, null],
    ]);
});

test('chase: a loss with no end before the next loss, or before the game ends, has no end', () => {
    const rows = run([...bots, lost(100, 1), lost(105, 1)]);
    assert.deepStrictEqual(rows.map(r => r[5]), [null, null]);
});
