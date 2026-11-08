'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'enemy_wave.sql'), 'utf8');

function run(lines, params) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ew-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, params || {});
    s.db.close();
    return out;
}

const wave = (t, team, lane, o) => line(t, `lane_ctl team=${team} lane=${lane} kind=wave wave=${Math.floor(t / 30) * 30} intent=back lever=${o.lever || 'none'} rej=${o.rej || 'shove:mode'} ew=${o.ew}${o.ewp !== undefined ? ` ewp=${o.ewp}` : ''}${o.ewd !== undefined ? ` ewd=${o.ewd}` : ''}`);
const pull = (t, pid, pos, lane, slot, res, div) => line(t, `pull_job pid=${pid} pos=${pos} lane=${lane} camp=1 slot=${slot} res=${res} why=${res} div=${div}`);

const lines = [
    line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    line(0, 'bot pid=4 hero=h4 team=2 pos=5'),
    line(0, 'bot pid=9 hero=h9 team=3 pos=5'),
    // Radiant bot at 5:02 reads their wave absent after Dire's pos5 pulled ok at slot 286 (in [270, 302)); the skip changed the set.
    pull(290, 9, 5, 3, 286, 'ok', 0.75),
    wave(302, 2, 3, { ew: 'a', ewp: 1, ewd: 19, lever: 'predeny+feed', rej: 'pull:ew;shove:mode' }),
    // Dire top at 5:32 reads absent with no enemy pull in the window (a Radiant pull on another lane, and one too early); its
    // pull was not on offer (no support), so no ewp and the real refusal stays.
    pull(320, 4, 5, 3, 316, 'ok', 0.5),
    pull(295, 4, 5, 1, 290, 'ok', 0.5),
    wave(332, 3, 1, { ew: 'a', rej: 'pull:no_sup;shove:mode' }),
    // Present and unknown reads are not rows; a Dire ok pull at 346 is caught by no absent read.
    wave(362, 2, 3, { ew: 'p', lever: 'pull' }),
    wave(392, 2, 3, { ew: 'u', lever: 'pull' }),
    pull(350, 9, 5, 3, 346, 'ok', 1),
    wave(422, 2, 3, { ew: 'p' }),
    // Our own pull on the lane of the absent read is not joined (it is the enemy team's pulls that explain their wave).
    pull(300, 4, 5, 3, 296, 'fail', 0),
];

test('enemy_wave: one row per absent read joined to the enemy pulls in its window', () => {
    const out = run(lines);
    assert.deepStrictEqual(out.map(r => [r.team, r.lane, r.t, r.ewd, r.ewp, r.skip, r.epid, r.slot, r.res, r.div]), [
        [2, 3, 302, 19, 1, 1, 9, 286, 'ok', 0.75],
        [3, 1, 332, null, null, 1, null, null, null, null],
    ]);
});

test('enemy_wave: the summary counts the reads, the skip, the explained reads and the enemy pulls caught', () => {
    const out = run(lines, { sum: 1 });
    assert.strictEqual(out.length, 1);
    const r = out[0];
    assert.strictEqual(r.n, 2);
    assert.strictEqual(r.skipped, 2);
    assert.strictEqual(r.ewp1, 1);
    assert.strictEqual(r.skipped, 2);
    assert.strictEqual(r.pulled, 1);
    assert.strictEqual(r.enemy_ok, 4);
    assert.strictEqual(r.caught, 1);
});
