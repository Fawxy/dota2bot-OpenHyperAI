'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;

test('shadow choice: seconds OHA would have picked attack, team_roam or roam and did not, by our module; unread reasons; held seconds', () => {
    const sh = (t, f) => line(t, `choice pid=1 kind=shadow ${f}`);
    const lines = [
        line(0, 'bot pid=1 hero=h1 team=2 pos=1'),
        // Team roam is OHA's top, held at 0 after its code: two seconds lost to the borrowed hold.
        sh(100, 'win=laning d_laning=0.300 d_team_roam=0.700 d_roam=-drive d_attack=-ours top=team_roam tv=0.700 how=zeroed by="ArbiterDrive:DriveAfter borrowed(lane)"'),
        sh(101, 'win=laning d_laning=0.300 d_team_roam=0.700 d_roam=-drive d_attack=-ours top=team_roam tv=0.700 how=zeroed by="ArbiterDrive:DriveAfter borrowed(lane)"'),
        // Probed roam would have won: zeroed before its code. The gap to the next line is capped at 2 s.
        sh(102, 'win=laning d_laning=0.300 d_team_roam=0.700 d_roam=0.800 d_attack=-ours top=roam tv=0.800 how=zeroed by=ArbiterDrive:DriveDecide(lane) pr=roam'),
        // Laning is OHA's top and holds: no lost seconds.
        sh(110, 'win=laning d_laning=0.900 d_team_roam=0.700 d_roam=-drive d_attack=0.100 top=laning'),
        sh(111, 'win=laning d_laning=0.900 d_team_roam=0.700 d_roam=-drive d_attack=0.100 top=laning'),
        // A cause with no module keeps its `how`; the hero's last line runs to the game's last event (capped at 2 s).
        sh(120, 'win=laning d_laning=0.300 d_team_roam=0.100 d_roam=0.200 d_attack=0.500 top=attack tv=0.500 how=valve'),
        line(121.5, 'bot pid=2 hero=h2 team=2 pos=2'),
        // Another run's line is its own label.
        line(0, 'choice pid=7 kind=pull go=1'),
    ];
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-shadow-')), 'a.log');
    fs.writeFileSync(f, lines.join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'shadow_choice.sql'), 'utf8');
    const rows = q => s.query(sql, q).map(r => [r.hero, r.part, r.mode, r.cause, r.secs]);
    assert.deepStrictEqual(rows({ part: 'lost' }), [
        ['h1', 'lost', 'roam', 'zeroed ArbiterDrive:DriveDecide(lane)', 2],
        ['h1', 'lost', 'team_roam', 'zeroed ArbiterDrive:DriveAfter borrowed(lane)', 2],
        ['h1', 'lost', 'attack', 'valve', 1.5],
    ]);
    assert.deepStrictEqual(rows({ part: 'unread' }), [
        ['h1', 'unread', 'roam', 'drive', 5],
        ['h1', 'unread', 'attack', 'ours', 4],
    ]);
    assert.deepStrictEqual(rows({ part: 'win' }), [['h1', 'win', 'laning', null, 8.5]]);
    assert.deepStrictEqual(rows({ part: 'lost', until: 101 }), [['h1', 'lost', 'team_roam', 'zeroed ArbiterDrive:DriveAfter borrowed(lane)', 1]]);
    s.db.close();
});
