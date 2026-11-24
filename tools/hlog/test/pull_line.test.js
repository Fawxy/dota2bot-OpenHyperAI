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
    const out = s.query(sql, { like: null, to: null, win: null, lead: null, first: null, ...params });
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
const snap = (t, pid, x, y) => line(t, `snap pid=${pid} x=${x} y=${y} alive=1 hp=100`);
const want = (t, pid, slot, extra = '') => line(t, `choice pid=${pid} kind=pull go=0 want=1 lane=3 slot=${slot}${extra}`);

test('the ledger of a wanted window: each of our creeps once from the two logs, by who took it; their creeps the same way round', () => {
    const out = run([...bots,
        want(190, 5, 200, ' why=off src=shadow'),
        // an own creep's death is in the owner's log only with a living hero of its team within 1,500 in the second before it
        snap(209.7, 1, 30, -6000), snap(211.8, 5, 60, -6000), snap(214.5, 1, 1000, -7500), snap(215.5, 1, 1000, -7500), snap(222.6, 6, 10, -6000),
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
    // a narrowed window, 15 to 55 s after the slot: of deaths at slot + 10, + 20 and + 60 only the middle one counts.
    const narrow = run([...bots, want(190, 5, 200), theirView(210, 0, 6), theirView(220, 0, 6), theirView(260, 0, 6)], { lead: 15, win: 55 });
    assert.deepStrictEqual(narrow.map(r => [r.wanted, r.o_dead]), [[1, 1]]);
});

test('the wanted wave\'s own creeps: named by lane and born wherever and whenever they die, each taken by its mutual-nearest sighting in the other log', () => {
    let cid = 0;
    const wcd = (t, x, y, by, born = 180.1, lane = 'bot', kind = 'melee') =>
        line(t, `wave_creep_death team=2 kind=${kind} x=${x} y=${y} hp=0.05 by=${by} cid=${++cid} lane=${lane} born=${born}`);
    const out = run([...bots,
        // slot 200 pulls the wave that spawned at 3:00 (floor(199 / 30) = 6).
        want(190, 5, 200),
        // at the bot pull camp (camp 8, -721, -7696), seen by nobody of theirs: other, at a camp.
        wcd(215, -700, -7650, 'none'),
        // in lane: their pos 1's last hit; our deny; their tower's.
        wcd(230, 0, -6000, 'none'), theirView(230.2, 10, 6),
        wcd(231, 100, -6000, 5), theirView(231.1, 100, 'none'),
        wcd(232, 300, -6000, 'none'), theirView(232.1, 300, 'none', 1),
        // two at once 200 apart: one sighting their pos 5's last hit, the other no one's; each pairs with its own.
        wcd(240, 1000, -6000, 'none'), wcd(240, 1200, -6000, 'none'), theirView(240.1, 1010, 8), theirView(240.1, 1190, 'none'),
        // 120 s after the slot, past the window: still the wave's, their pos 1's.
        wcd(320, 2000, -6000, 'none'), theirView(320.1, 2000, 6),
        // not the wave: the next one, and the same spawn on the top lane.
        wcd(250, 0, -6000, 'none', 210.1), wcd(250, -6000, 6000, 'none', 180.1, 'top'),
    ]);
    assert.deepStrictEqual(out.map(r => [r.team, r.lane, r.w_n, r.w_lh, r.w_lh_core, r.w_deny, r.w_tower, r.w_other, r.w_camp]),
        [[2, 3, 7, 3, 2, 1, 1, 2, 1]]);
});

const { teamGames, pairs, nullPairs, diffStats } = require('../pull_line');

test('pairs: an on game\'s seat team against the off game of its run, lineup and repetition; the interval is Student t on the differences', () => {
    const row = (game_id, team, lane, o_dead, o_lh) => ({ game_id, team, lane, wanted: 1, started: 0, hit: 0, diverted: 0, o_dead, o_lh, o_lh_core: 0, o_deny: 0, o_tower: 0, o_other: 0,
        e_dead: 10, e_lh: 0, e_lh_core: 5, e_deny: 0, e_tower: 0, e_other: 0 });
    const labels = new Map([[1, 'x1_A_off_1'], [2, 'x1_A_onrad_1'], [3, 'x1_A_ondire_1'], [4, 'x1_B_off_2'], [5, 'x1_B_onrad_2'], [6, 'x2_A_off_1']]);
    const games = teamGames([
        // the off game of A: Radiant 0.5 over two lanes, Dire 0.4.
        row(1, 2, 1, 10, 6), row(1, 2, 3, 10, 4), row(1, 3, 1, 10, 4),
        // on Radiant 0.3 (its Dire, the other side, is not a pair); on Dire 0.3.
        row(2, 2, 3, 10, 3), row(2, 3, 1, 10, 9), row(3, 3, 1, 10, 3), row(3, 2, 1, 10, 9),
        // B: off 0.5, on 0.2; another run's off game of A pairs with nothing here.
        row(4, 2, 3, 10, 5), row(5, 2, 3, 10, 2), row(6, 2, 3, 10, 0),
        // a game the runs do not name.
        row(9, 2, 3, 10, 0),
    ], labels);
    const ps = pairs(games, 'on', 'off');
    assert.deepStrictEqual(ps.map((p) => [p.on.label, p.on.team, p.off.label, Number((p.on.lh - p.off.lh).toFixed(2))]),
        [['x1_A_onrad_1', 2, 'x1_A_off_1', -0.2], ['x1_A_ondire_1', 3, 'x1_A_off_1', -0.1], ['x1_B_onrad_2', 2, 'x1_B_off_2', -0.3]]);
    const s = diffStats(ps, 'lh');
    // mean -0.2, sd 0.1, t(2 df) 4.303: half-width 4.303 * 0.1 / sqrt(3).
    assert.deepStrictEqual([s.n, s.mean.toFixed(3), s.sd.toFixed(3), s.half.toFixed(3)], [3, '-0.200', '0.100', '0.248']);
    assert.deepStrictEqual(nullPairs(games, 'off').map((p) => [p.on.label, p.off.label, p.on.team]), [['x2_A_off_1', 'x1_A_off_1', 2]]);
});

const waveSql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'pull_line_waves.sql'), 'utf8');

test('by wave: each own wave once, whether the trigger wanted it, the camp it saw, and the neutrals a diverted pull met', () => {
    let cid = 0;
    const wcd = (t, x, y, born) => line(t, `wave_creep_death team=2 kind=melee x=${x} y=${y} hp=0.05 by=none cid=${++cid} lane=bot born=${born}`);
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-plw-')), 'a.log');
    const lines = [...bots,
        // wave 6 (3:00): wanted with the camp seen at 7, pulled into 7 neutrals; two die at the camp, one to their pos 1 in lane.
        want(190, 5, 200, ' cn=7 cs=1'),
        line(215, 'pull_job pid=5 pos=5 lane=3 camp=8 slot=200 res=ok why=ok hit=1 dt=1 nn=7'),
        wcd(215.5, -700, -7650, 180.1), wcd(216, -720, -7690, 180.1), wcd(240, 0, -6000, 180.1), theirView(240.1, 0, 6),
        // wave 7: wanted, the pull started but did not divert (dt under 0.75), so no nn.
        want(220, 5, 230),
        line(235, 'pull_job pid=5 pos=5 lane=3 camp=8 slot=230 res=ok why=ok hit=1 dt=0.5 nn=3'),
        wcd(260, 0, -6000, 210.1),
        // wave 8: not wanted, still a row; then the wave spawned at 9:00, past :to (525).
        wcd(290, 0, -6000, 240.1), wcd(570, 0, -6000, 540.1),
    ];
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, lines.sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    const out = s.query(waveSql, { like: null, to: null });
    s.db.close();
    assert.deepStrictEqual(out.map(r => [r.team, r.lane, r.wave, r.wanted, r.cn, r.diverted, r.nn, r.w_n, r.w_lh, r.w_lh_core, r.w_camp]),
        [[2, 3, 6, 1, 7, 1, 7, 3, 1, 1, 2], [2, 3, 7, 1, null, 0, null, 1, 0, 0, 0], [2, 3, 8, 0, null, 0, null, 1, 0, 0, 0]]);
});

test('strong-camp pairs: the on game\'s waves pulled into the bar or more, against the same lane and wave of its off game', () => {
    const { strongPairs } = require('../pull_line');
    const w = (lane, wave, diverted, nn, w_n, w_lh, w_camp) => ({ lane, wave, diverted, nn, w_n, w_lh, w_camp });
    const ps = [
        { on: { label: 'x_A_onrad_1', team: 2, waves: [
            // strong at 7 and at exactly 6, one under the bar (4), and a strong one on the top lane.
            w(3, 6, 1, 7, 4, 0, 4), w(3, 10, 1, 6, 4, 1, 3), w(3, 8, 1, 4, 4, 2, 1), w(1, 6, 1, 8, 4, 0, 4)] },
          off: { waves: [
            // the same waves unpulled; bot wave 8 (the on game's weak pull) and mid wave 6 are not compared.
            w(3, 6, 0, null, 4, 2, 0), w(3, 10, 0, null, 3, 1, 0), w(3, 8, 0, null, 4, 3, 0), w(1, 6, 0, null, 4, 1, 0), w(2, 6, 0, null, 4, 4, 0)] } },
        // no strong wave: no pair.
        { on: { label: 'x_A_onrad_2', team: 2, waves: [w(3, 6, 1, 3, 4, 2, 1)] }, off: { waves: [w(3, 6, 0, null, 4, 2, 0)] } },
    ];
    const sp = strongPairs(ps, 6);
    assert.deepStrictEqual(sp.map(p => [p.label, p.on.waves, p.on.w_n, p.on.w_lh, p.on.w_camp, p.off.waves, p.off.w_n, p.off.w_lh]),
        [['x_A_onrad_1', 3, 12, 1, 11, 3, 11, 4]]);
});
