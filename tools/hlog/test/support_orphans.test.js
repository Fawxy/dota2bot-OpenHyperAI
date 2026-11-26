'use strict';
// queries/support_orphans.sql: a support's orphan last hits (their creep, support in reach, no core in reach), its deny chances
// (our creeps with it in reach), and where the two fall within the window for the same support. Bot lane at y = -6256 (x 0 is on the
// lane's polyline). Radiant: sniper (pid 0, pos 2), lion (pid 1, pos 5, range 600). Dire: zuus (pid 5, pos 2).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const Y = -6256;
const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const seen = (team, cid, type) => line(60, `unit_seen team=${team} cid=${cid} kind=lane type=${type} lane=bot x=0 y=${Y}`);
const gone = (t, team, cid, by = 'none') => line(t, `unit_gone team=${team} cid=${cid} x=0 y=${Y} hp=0.1 by=${by}`);
const taker = (t, team, cid, by, kind) => line(t, `creep_death team=${team} kind=${kind} x=0 y=${Y} hp=0.05 by=${by} tw=0 cid=${cid}`);
const snap = (t, pid, x, ar = 550) => line(t, `snap pid=${pid} x=${x} y=${Y} alive=1 hp=90 ar=${ar}`);
const around = (t, pid, x, ar) => [snap(t - 0.5, pid, x, ar), snap(t + 0.5, pid, x, ar)];

/**
 * Dire's creeps (Radiant's `theirs`), lion 400 away (in reach) unless said:
 * O1 100  ranged, lion's last hit, sniper 3,000 away                    orphan, paid by the support
 * D1 101  Radiant melee, lion denies                                    deny chance, within 1 s of O1: clash
 * O2 200  ranged, nobody                                                orphan, paid nobody, no deny chance near
 * D2 300  Radiant melee, zuus last-hits it                              deny chance, their last hit, 100 s from any orphan
 * N1 400  ranged, sniper's last hit, sniper 300 away                    a core in reach: not an orphan
 * O3 550  ranged, their zuus denies it                                  orphan, denied by them
 * M1 500  melee, nobody                                                 orphan unless `kind` leaves melee out
 */
function load() {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-support-orphans-'));
    const file = path.join(dir, '2026-11-26T00-00-00-so_A_off_1.log');
    const lines = [
        line(-90, 'bot pid=0 hero=sniper team=2 pos=2'), line(-90, 'bot pid=1 hero=lion team=2 pos=5'), line(-90, 'bot pid=5 hero=zuus team=3 pos=2'),
        ...[1, 2, 3, 4].map(c => seen(3, c, c < 4 ? 'npc_dota_creep_badguys_ranged' : 'npc_dota_creep_badguys_melee')),
        ...[5, 8].map(c => seen(3, c, 'npc_dota_creep_badguys_ranged')),
        ...[6, 7].map(c => seen(2, c, 'npc_dota_creep_goodguys_melee')),
        gone(100, 3, 1), taker(100, 2, 41, 1, 'ranged'),
        gone(101, 2, 6, 1),
        gone(200, 3, 2), taker(200, 2, 42, 'none', 'ranged'),
        gone(300, 2, 7), taker(300, 3, 43, 5, 'melee'),
        gone(400, 3, 3), taker(400, 2, 44, 0, 'ranged'),
        gone(550, 3, 8, 5),
        gone(500, 3, 4), taker(500, 2, 45, 'none', 'melee'),
    ];
    for (const t of [100, 101, 200, 300, 400, 500, 550]) lines.push(...around(t, 1, -400, 600), ...around(t, 0, t === 400 ? -300 : -3000));
    lines.push(...around(300, 5, 400, 500));
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(file, lines.sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const store = new Store(':memory:');
    store.ingest(file);
    store.refreshViews();
    return store;
}
const sqlOf = (name) => fs.readFileSync(path.join(__dirname, '..', 'queries', `${name}.sql`), 'utf8');
const like = '%so_A_off_1%';
const cols = ['team', 'orph', 'orph_sup', 'orph_core', 'orph_dn', 'orph_unpaid', 'dch', 'dch_sup', 'dch_core', 'dch_them', 'dch_other', 'clash', 'dclash'];
const pick = r => cols.map(c => r[c]);

test('support_orphans: orphans need their creep of a named kind, the support and no core in reach; a clash needs a deny chance in the window', () => {
    const store = load();
    assert.deepStrictEqual(store.query(sqlOf('support_orphans'), { like, kind: 'ranged' }).map(pick), [
        [2, 3, 1, 0, 1, 1, 2, 1, 0, 1, 0, 1, 1],
        [3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ]);
    assert.deepStrictEqual(store.query(sqlOf('support_orphans'), { like }).map(r => [r.team, r.orph, r.orph_unpaid, r.clash]), [[2, 4, 2, 1], [3, 0, 0, 0]],
        'with kind unset the melee creep nobody took is an orphan too');
    assert.deepStrictEqual(store.query(sqlOf('support_orphans'), { like, kind: 'melee,siege' }).map(r => [r.team, r.orph, r.orph_unpaid]), [[2, 1, 1], [3, 0, 0]]);
    assert.deepStrictEqual(store.query(sqlOf('support_orphans'), { like, win: 0.5 }).map(r => [r.team, r.clash, r.dclash]), [[2, 0, 0], [3, 0, 0]],
        'a deny chance 1 s from the orphan is outside a 0.5 s window');
});

test('support_orphans: sum = 1 gives means per team-game by arm and side', () => {
    const rows = load().query(sqlOf('support_orphans'), { like, sum: 1 }).map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.tg, r.m_orph, r.m_dch, r.s_clash, r.s_dclash]), [[2, 2, 1, 1, 1]]);
});
