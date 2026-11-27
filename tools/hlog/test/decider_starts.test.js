'use strict';
// The decider's begins by row and the mode the hero was taken from (queries/decider_starts.sql). Two games of one batch, our arm
// on Radiant (seat rad): pid 0 (pos 1) and pid 3 (pos 5) Radiant, pid 5 (pos 1) Dire.
//   game 1: pid 0 creep from laning twice, creep from attack once; pid 3 pull from roam; pid 5 creep from team_roam;
//           a decider line with no begin, a non-decider line with beg, and a begin past :until do not count
//   game 2: pid 0 creep from laning once; a begin from before oha-start-from (no bfrom) reads `-`
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const dec = (t, pid, beg, bfrom) => line(t, `choice pid=${pid} kind=decider held=${beg} win=farm hs=hard beg=${beg} btgt=creep:1 bby=${t + 1}` +
    (bfrom ? ` bfrom=${bfrom}` : ''));
const bots = () => [
    line(-90, 'bot pid=0 hero=h0 team=2 pos=1'), line(-90, 'bot pid=3 hero=h3 team=2 pos=5'), line(-90, 'bot pid=5 hero=h5 team=3 pos=1'),
];

function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-decider-starts-'));
    const write = (name, lines) => {
        const file = path.join(dir, `2026-11-27T00-00-00-${name}.log`);
        const at = l => Number(l.match(/t=(\S+)/)[1]);
        fs.writeFileSync(file, lines.sort((x, y) => at(x) - at(y)).join('\n') + '\n');
        return file;
    };
    const store = new Store(':memory:');
    store.ingest(write('ds1_A_onrad_1', [...bots(),
        dec(100, 0, 'creep', 'laning'), dec(110, 0, 'creep', 'laning'), dec(120, 0, 'creep', 'attack'),
        dec(130, 3, 'pull', 'roam'), line(132, 'choice pid=3 kind=decider ref=stack btgt=camp:1 bfrom=roam why=fight'),
        line(135, 'choice pid=3 kind=decider held=- win=roam'), dec(140, 5, 'creep', 'team_roam'),
        line(150, 'choice pid=0 kind=decider held=- win=laning'),
        line(160, 'choice pid=0 kind=pull go=0 want=1 why=late src=own lane=1 slot=160 beg=pull'),
        dec(700, 0, 'creep', 'attack'),
    ]));
    store.ingest(write('ds1_A_onrad_2', [...bots(), dec(100, 0, 'creep', 'laning'), dec(200, 0, 'stack', null)]));
    store.refreshViews();
    return store;
}

test('decider_starts: begins by row and mode, per team-game, with the fight modes marked', () => {
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'decider_starts.sql'), 'utf8');
    const rows = load().query(sql, { batch: 'ds1' }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.side, r.role, r.beg, r.bfrom, r.n, r.fight, r.team_games, r.per_tg]), [
        ['opp', 'core', 'creep', 'team_roam', 1, 1, 2, 0.5],
        ['test', 'core', 'creep', 'laning', 3, 0, 2, 1.5],
        ['test', 'core', 'creep', 'attack', 1, 1, 2, 0.5],
        ['test', 'core', 'stack', '-', 1, 0, 2, 0.5],
        ['test', 'support', 'pull', 'roam', 1, 1, 2, 0.5],
    ]);
    assert.ok(rows.every(r => r.batch === 'ds1' && r.arm === 'on'));
    // Held: to the hero's next decider line holding another row or none, or a new begin; a refusal line does not end it.
    // pid 0, game 1: laning 100 -> 110 -> 120 (begins), attack 120 -> 150 (held=-); game 2: laning 100 -> 200 (a begin).
    // pid 3: roam 130 -> 135 (held=-; the refusal at 132 does not count). pid 5: team_roam 140, nothing after: 0.
    const held = Object.fromEntries(rows.map(r => [`${r.side} ${r.beg} ${r.bfrom}`, r.held_s]));
    assert.deepStrictEqual(held, { 'opp creep team_roam': 0, 'test creep laning': 120, 'test creep attack': 30, 'test stack -': 0, 'test pull roam': 5 });
    assert.strictEqual(rows.find(r => r.bfrom === 'attack').held_tg, 15);
});
