'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { heldShare, format } = require('../held');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
// Radiant (ours, `_rad_`): pos 1 (pid 1), pos 2 (pid 2), pos 5 (pid 3). Dire: pos 1 (pid 5).
const BOTS = [[1, 2, 1], [2, 2, 2], [3, 2, 5], [5, 3, 1]].map(([pid, team, pos]) => line(-60, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos}`));

/** A hero's snapshots each second to 600; it dies at `dieAt` (last living snap there, respawn snap at its fountain 30 s on). */
function life(pid, { dieAt, retreat = [] } = {}) {
    const out = [];
    for (let t = 0; t <= 600; t++) {
        if (dieAt !== undefined && t > dieAt && t < dieAt + 30) continue;
        const fell = dieAt !== undefined && t >= dieAt + 30;
        const [x, y] = fell ? [-6850, -6461] : [0, 0];
        const mode = retreat[0] <= t && t < retreat[1] ? 'retreat' : 'laning';
        out.push(line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=100 lh=0 deaths=${fell ? 1 : 0} mode=${mode} ln=mid ld=100 hit=0 ah=0 at=0 ac=0 an=0 hc=0`));
    }
    return out;
}

function store(name, lines) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-held-'));
    const s = new Store(':memory:');
    const f = path.join(dir, `2026-11-19T00-00-00-${name}.log`);
    // A log's clock only runs forward: a time that goes back starts a new game.
    const at = (l) => Number(l.match(/t=(-?[\d.]+)/)[1]);
    const ordered = lines.map((l, i) => [at(l), i, l]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map((x) => x[2]);
    fs.writeFileSync(f, [...BOTS, ...ordered].join('\n') + '\n');
    s.ingest(f);
    s.refreshViews();
    return s;
}

test('held share, hold ends and deaths split by who was driving', () => {
    const s = store('held_A_rad_1', [
        line(-15, 'arb pid=1 ph=own'), line(-15, 'arb pid=3 ph=own'),
        // pid 2 never logs ph=own: OHA plays it from the start.
        line(300, 'arb pid=1 ph=end why=lost'),
        ...life(1, { dieAt: 400, retreat: [350, 370] }),
        ...life(2, { dieAt: 500 }),
        ...life(3, { dieAt: 200, retreat: [100, 130] }),
        ...life(5, { dieAt: 150 }),
    ]);
    const a = heldShare(s, ['held']);
    assert.strictEqual(a.heroSec, 1800);
    assert.strictEqual(a.heldSec, 900);
    assert.deepStrictEqual([1, 2, 3, 4, 5].map((p) => a.byPos[p].heldSec), [300, 0, 0, 0, 600]);
    assert.deepStrictEqual(a.ends, { lost: { before: 1, after: 0 } });
    // The pos 1 death at 400 is after its hold ended and the pos 2 death at 500 is a hero never held; the pos 5 death at 200
    // is under its hold; the Dire death is not ours.
    assert.deepStrictEqual(a.deaths, { held: 1, oha: 2 });
    assert.strictEqual(a.retreatSec.held, 30);
    assert.strictEqual(a.retreatSec.oha, 20);
    assert.match(format(a, 600), /team   50\.0%/);
});

test('a hold that ends after the window is held to the window and counted as an end after it', () => {
    const s = store('held_A_rad_1', [
        line(-15, 'arb pid=1 ph=own'), line(700, 'arb pid=1 ph=end why=tower'),
        ...life(1), ...life(2), ...life(3), ...life(5),
    ]);
    const a = heldShare(s, ['held']);
    assert.strictEqual(a.heldSec, 600);
    assert.deepStrictEqual(a.ends, { tower: { before: 0, after: 1 } });
});
