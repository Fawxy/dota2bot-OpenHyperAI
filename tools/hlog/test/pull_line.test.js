'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pull_line.sql'), 'utf8');

function run(lines, params = {}) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-pl-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, { like: null, to: null, win: null, first: null, ...params });
    s.db.close();
    return out;
}

// Team 2: pid 1 its pos 1, pid 5 its pos 5 (the puller). Team 3: pid 6 its pos 1, pid 8 its pos 5. The bot lane (3) runs
// along y = -6000 (y - x under -4,000 for x over -2,000).
const bots = [
    line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
    line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
    line(0, 'bot pid=6 hero=h6 team=3 pos=1'),
    line(0, 'bot pid=8 hero=h8 team=3 pos=5'),
];
// A team-2 creep as team 3 saw it die, and as team 2 saw it; a team-3 creep as team 2 saw it.
const theirView = (t, x, by, tw = 0, kind = 'melee') => line(t, `creep_death team=3 kind=${kind} x=${x} y=-6000 hp=0.05 by=${by} tw=${tw}`);
const ourView = (t, x, by, y = -6000, kind = 'melee') => line(t, `own_creep_death team=2 kind=${kind} x=${x} y=${y} hp=0.05 by=${by}`);
const want = (t, pid, slot, extra = '') => line(t, `choice pid=${pid} kind=pull go=0 want=1 lane=3 slot=${slot}${extra}`);

test('the ledger of a wanted window: each of our creeps once from the two logs, by who took it; their creeps the same way round', () => {
    const out = run([...bots,
        want(190, 5, 200, ' why=off src=shadow'),
        // their core's last hit, seen by both teams: one death.
        theirView(210, 0, 6), ourView(210.2, 30, 'none'),
        // their support's last hit, seen only by them.
        theirView(211, 0, 8),
        // our deny: their log says none, ours names the denier.
        theirView(212, 50, 'none'), ourView(212.3, 60, 5),
        // their tower's, a second after the deny and 50 from it (not the deny's), and one nobody took.
        theirView(213, 0, 'none', 1), theirView(214, 0, 'none', 0, 'ranged'),
        // at the camp, seen only by us (the pulled wave): died to the neutrals, and one the puller denied.
        ourView(215, 1000, 'none', -7500), ourView(216, 1000, 5, -7500),
        // outside: before the slot, at slot + 75, and on the mid lane.
        theirView(199, 0, 6), theirView(275, 0, 6), line(220, 'creep_death team=3 kind=melee x=0 y=0 hp=0.05 by=6 tw=0'),
        // their creeps: our core's last hit, our support's, their deny, our tower's.
        line(221, 'creep_death team=2 kind=melee x=0 y=-6000 hp=0.05 by=1 tw=0'),
        line(222, 'creep_death team=2 kind=melee x=0 y=-6000 hp=0.05 by=5 tw=0'),
        line(223, 'creep_death team=2 kind=melee x=0 y=-6000 hp=0.05 by=none tw=0'),
        line(223.1, 'own_creep_death team=3 kind=melee x=10 y=-6000 hp=0.05 by=6'),
        line(224, 'creep_death team=2 kind=ranged x=0 y=-6000 hp=0.05 by=none tw=1'),
    ]);
    assert.deepStrictEqual(out.map(r => [r.team, r.lane, r.wanted, r.started, r.o_dead, r.o_lh, r.o_lh_core, r.o_deny, r.o_tower, r.o_other,
        r.e_dead, r.e_lh, r.e_lh_core, r.e_deny, r.e_tower, r.e_other]),
        [[2, 3, 1, 0, 7, 2, 1, 2, 1, 2, 4, 2, 1, 1, 1, 0]]);
});

test('wanted slots: one per team, lane and pulled wave whichever line names it; overlapping windows count a death once; the funnel reads that team\'s pull on the wave', () => {
    const out = run([...bots,
        // the pulling team: slot 200 started and diverted, 230 started and failed, 260 wanted and not started.
        line(190, 'choice pid=5 kind=pull go=1 want=1 lane=3 slot=200.4'),
        line(215, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=200.1 res=ok why=ok hit=1 dt=1'),
        line(220, 'choice pid=5 kind=pull go=1 want=1 lane=3 slot=230'),
        line(232, 'pull_job pid=5 pos=5 lane=3 camp=13 slot=230 res=fail why=cancelled:one hit=0'),
        want(250, 5, 260),
        // not wanted, and past :to.
        line(280, 'choice pid=5 kind=pull go=0 want=0 lane=3 slot=290'),
        want(520, 5, 530),
        // the other team's shadow on the same lane id and wave.
        want(191, 8, 200.9, ' why=off src=shadow'),
        // in the windows of 200, 230 and 260 at once.
        theirView(262, 0, 6),
        // only in 260's.
        theirView(330, 0, 6),
    ]);
    assert.deepStrictEqual(out.map(r => [r.team, r.wanted, r.started, r.hit, r.diverted, r.first_slot, r.o_dead, r.o_lh, r.e_dead, r.e_lh]),
        [[2, 3, 2, 1, 1, 200.4, 2, 2, 0, 0], [3, 1, 0, 0, 0, 200.9, 0, 0, 1, 1]]);
    const first = run([...bots, want(190, 5, 200), want(250, 5, 260), theirView(262, 0, 6), theirView(330, 0, 6)], { first: 1 });
    assert.deepStrictEqual(first.map(r => [r.wanted, r.o_dead]), [[1, 1]]);
});
