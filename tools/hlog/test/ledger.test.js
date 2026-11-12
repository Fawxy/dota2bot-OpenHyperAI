'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');
const { ledger, summary } = require('../ledger');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
// Radiant pos 1 and pos 5 against Dire pos 1 and pos 5; Radiant is ours (the `_rad_` seat).
const BOTS = [[1, 2, 1], [2, 2, 5], [5, 3, 1], [6, 3, 5]].map(([pid, team, pos]) => line(-60, `bot pid=${pid} hero=h${pid} team=${team} pos=${pos}`));
const snap = (t, pid, x, y, o = {}) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=${o.hp ?? 100} lh=${o.lh ?? 0} deaths=${o.d ?? 0}` +
    ` mode=laning ln=${o.ln ?? 'mid'} ld=100 hit=${o.hit ?? 0} ah=${o.ah ?? 0} at=${o.at ?? 0} ac=0 an=0 hc=0`);

function store(logs) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ledger-'));
    const s = new Store(':memory:');
    for (const [name, lines] of Object.entries(logs)) {
        const f = path.join(dir, `2026-11-13T00-00-00-${name}.log`);
        fs.writeFileSync(f, [...BOTS, ...lines].join('\n') + '\n');
        s.ingest(f);
    }
    s.refreshViews();
    return s;
}

/** Radiant pos 1 at mid is hit by both Dire heroes from 92 s and dies at 100 s; `ally(t)` places Radiant pos 5. */
function death({ ally, towerAt }) {
    const lines = [];
    for (let t = 80; t <= 100; t++) {
        const hit = t >= 92 ? 1 : 0;
        lines.push(snap(t, 1, 0, 0, { hp: Math.max(5, 100 - 5 * (t - 80)), hit, ah: hit ? 2 : 0, at: t === towerAt ? 1 : 0 }));
        lines.push(snap(t, 5, 300, 0), snap(t, 6, 0, 300));
        const [x, y] = ally(t);
        lines.push(snap(t, 2, x, y));
    }
    lines.push(snap(130, 1, -6850, -6461, { d: 1 }));
    return lines;
}

test('a death takes one cause: a partner reached only as it died is not in the fight; a tower in the last 5 s comes first', () => {
    const s = store({
        fled_A_rad_1: death({ ally: (t) => (t === 100 ? [500, 0] : [3000, 0]) }),
        pair_A_rad_1: death({ ally: () => [500, 0] }),
        tower_A_rad_1: death({ ally: () => [500, 0], towerAt: 97 }),
    });
    const cause = (run) => ledger(s, [run]).rows.deaths.map((d) => [d.side, d.attackers, d.allies, d.cause]);
    assert.deepStrictEqual(cause('fled'), [['ours', 2, 0, 'outnumbered_alone']]);
    assert.deepStrictEqual(cause('pair'), [['ours', 2, 1, 'even_numbers']]);
    assert.deepStrictEqual(cause('tower'), [['ours', 2, 1, 'tower']]);
});

const BOT_LANE = [-360, -6256];
const creep = (t, o) => line(t, `creep_death team=2 kind=melee x=${BOT_LANE[0]} y=${BOT_LANE[1]} hp=10 by=${o.by ?? 'none'}` +
    (o.p1d === undefined ? '' : ` p1d=${o.p1d} p1r=150 p1t=0`));

test('lane creeps: the other team\'s own deaths fill the pool, causes come from the lane core, and the lines sum to the gap', () => {
    const lines = [];
    for (let t = 60; t <= 130; t++) {
        const atBase = t >= 108 && t <= 112;
        lines.push(snap(t, 1, atBase ? -6850 : BOT_LANE[0], atBase ? -6461 : BOT_LANE[1] + 200, { ln: 'bot', lh: t >= 100 ? 1 : 0 }));
        lines.push(snap(t, 5, 6000, -2000, { ln: 'bot' }));
    }
    lines.push(creep(100, { by: 1, p1d: 120 }));
    lines.push(creep(101, { p1d: 1000 }));
    // Seen only by Dire, the owner: Radiant's core was at its fountain.
    lines.push(line(110, `own_creep_death team=3 kind=melee x=${BOT_LANE[0]} y=${BOT_LANE[1]} hp=10 by=none`));
    const s = store({ lane_A_rad_1: lines });
    const r = ledger(s, ['lane']);
    assert.deepStrictEqual(r.rows.creeps.filter((c) => c.side === 'ours').map((c) => [c.src, c.cause]),
        [['seen', 'taken'], ['seen', 'held_back'], ['unseen', 'away_base']]);
    for (const measure of ['deaths', 'last_hits']) {
        const lines = summary(r).filter((l) => l.measure === measure);
        const total = lines.find((l) => l.line === 'total');
        const sum = lines.filter((l) => l.line !== 'total').reduce((a, l) => a + l.gap, 0);
        assert.ok(Math.abs(sum - total.gap) < 1e-9, `${measure}: lines sum to ${sum}, total gap ${total.gap}`);
    }
    assert.strictEqual(summary(r).find((l) => l.line === 'total' && l.measure === 'last_hits').ours, 1);
});
