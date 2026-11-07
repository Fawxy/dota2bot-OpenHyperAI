'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'core_pull.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-cp-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const wave = (team, lane, wave, o) => `lane_ctl team=${team} lane=${lane} kind=wave wave=${wave} rule=${o.rule || 'R1'} intent=${o.intent || 'back'} lever=${o.lever || 'none'} own=${o.own || 2000} tgt=900${o.rej ? ' rej=' + o.rej : ''}${o.pby ? ' pby=' + o.pby : ''}${o.nobody ? '' : ' core=1'}`;
const chk = (team, lane, wave, own) => `lane_ctl team=${team} lane=${lane} kind=chk wave=${wave} own=${own}`;
const pull = (pid, pos, lane, slot, res, died) => `pull_job pid=${pid} pos=${pos} lane=${lane} camp=1 slot=${slot} res=${res} why=${res} died=${died || 0}`;

test('core_pull: the offlane back waves by puller, the coverage count and the pos3 starts', () => {
    const out = run([
        line(0, 'bot pid=1 hero=h1 team=2 pos=3'),
        line(0, 'bot pid=3 hero=h3 team=2 pos=4'),
        line(0, 'bot pid=9 hero=h9 team=3 pos=3'),
        // Radiant top (offlane): the pos3 named and pulls ok, the clash then nearer the target.
        line(392, wave(2, 1, 390, { lever: 'predeny+pull', pby: 'core' })),
        line(410, pull(1, 3, 1, 408, 'ok')),
        line(437, chk(2, 1, 390, 1200)),
        // A wave with no puller (coverage), the clash further out at the check; one with nobody in lane and one under R6 are
        // no puller too but not coverage (no puller could have gone).
        line(422, wave(2, 1, 420, { rej: 'feed:nobody;pull:no_sup' })),
        line(467, chk(2, 1, 420, 2500)),
        line(512, wave(2, 1, 510, { rej: 'predeny:nobody;pull:no_sup', nobody: true })),
        line(542, wave(2, 1, 540, { rej: 'pull:no_sup', rule: 'R6' })),
        // Dire bot (offlane): the pos3's start cancelled, and it died in another.
        line(452, wave(3, 3, 450, { lever: 'pull', pby: 'core' })),
        line(470, pull(9, 3, 3, 468, 'fail')),
        line(500, pull(9, 3, 3, 498, 'fail', 1)),
        // Radiant bot is the safe lane: not counted; a hold wave is not counted.
        line(392, wave(2, 3, 390, { lever: 'pull', pby: 'sup' })),
        line(482, wave(2, 1, 480, { intent: 'hold' })),
    ]);
    const key = r => `${r.row}:${r.pby}:${r.okby}`;
    const by = Object.fromEntries(out.map(r => [key(r), r]));
    assert.strictEqual(by['wave:core:3'].n, 1);
    assert.strictEqual(by['wave:core:3'].nearer, 1);
    assert.strictEqual(by['wave:core:none'].n, 1);
    assert.strictEqual(by['wave:none:none'].no_puller, 3);
    assert.strictEqual(by['wave:none:none'].no_puller_in, 1);
    assert.strictEqual(by['wave:none:none'].nearer, 0);
    assert.strictEqual(by['start:core:all'].n, 3);
    assert.strictEqual(by['start:core:all'].ok, 0.33);
    assert.strictEqual(by['start_died:core:all'].n, 1);
    assert.strictEqual(out.filter(r => r.row === 'wave').reduce((a, r) => a + r.n, 0), 5);
});
