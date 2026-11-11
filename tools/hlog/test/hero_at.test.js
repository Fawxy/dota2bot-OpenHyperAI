'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const QUERY = fs.readFileSync(path.join(__dirname, '../queries/hero_at.sql'), 'utf8');

const NEW = [
    '[HEV] t=-90 ev=bot pid=3 hero=luna team=2 schema=2 build=abc pos=1',
    '[HEV] t=-90 ev=bot pid=4 hero=axe team=2 schema=2 build=abc pos=3',
    '[HEV] t=0 ev=drill ph=rep name=pull rep=1 input=on team=2 start=0',
    '[HEV] t=60 ev=inv pid=3 items="s0=flask:1 s1=tango:3"',
    '[HEV] t=60 ev=snap pid=3 x=10 y=20 alive=1 hp=90 mp=80 lvl=2 gold=300 nw=900 mode=laning by="laning 0.5 by oha" act=4 tgt=npc_dota_hero_axe tid=h4',
    '[HEV] t=61 ev=snap pid=3 x=11 y=20 alive=1 hp=85 mp=80 lvl=2 gold=310 nw=910 mode=laning act=1',
    '[HEV] t=61 ev=snap pid=4 x=0 y=0 alive=1 hp=50 mp=10 lvl=1 gold=100 nw=500 mode=farm act=1',
    '[HEV] t=65 ev=drill ph=rep name=pull rep=2 input=off team=2 start=65',
    '[HEV] t=70 ev=inv pid=3 items="s0=flask:1 s3=tango:2"',
    '[HEV] t=70 ev=snap pid=3 x=12 y=20 alive=0 hp=0 mp=80 lvl=3 gold=320 nw=920 mode=laning act=1',
].join('\n');

function open(text) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-heroat-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return { s, f };
}
const at = (s, f, p) => s.query(QUERY, { like: f, game: null, pid: null, hero: null, ...p }).map(r => ({ ...r }));

test('hero_at: the last snapshot, inventory and drill rep at or before t, never after', () => {
    const { s, f } = open(NEW);
    const [a] = at(s, f, { pid: 3, t: 62 });
    assert.deepStrictEqual([a.hero, a.snap_t, a.hp, a.lvl, a.gold, a.act, a.tgt, a.tid], ['luna', 61, 85, 2, 310, 1, null, null]);
    assert.deepStrictEqual([a.inv_t, a.inv], [60, 's0=flask:1 s1=tango:3']);
    assert.deepStrictEqual([a.drill, a.rep, a.input], ['pull', 1, 'on']);
    const [b] = at(s, f, { pid: 3, t: 60 });
    assert.deepStrictEqual([b.snap_t, b.by, b.tid, b.tgt], [60, 'laning 0.5 by oha', 'h4', 'npc_dota_hero_axe']);
    const [c] = at(s, f, { pid: 3, t: 100 });
    assert.deepStrictEqual([c.snap_t, c.alive, c.inv, c.rep, c.input], [70, 0, 's0=flask:1 s3=tango:2', 2, 'off']);
    s.db.close();
});

test('hero_at: a hero name and an m:ss clock pick the same row as pid and seconds', () => {
    const { s, f } = open(NEW);
    const byName = at(s, f, { hero: 'axe', t: '1:05' });
    assert.deepStrictEqual(byName.map(r => [r.pid, r.snap_t, r.hp, r.inv]), [[4, 61, 50, null]]);
    s.db.close();
});

test('hero_at: before the first snapshot the row keeps the hero with empty state', () => {
    const { s, f } = open(NEW);
    const [r] = at(s, f, { pid: 3, t: 30 });
    assert.deepStrictEqual([r.hero, r.snap_t, r.hp, r.inv, r.rep], ['luna', null, null, null, 1]);
    s.db.close();
});

test('hero_at: a log from before ev=inv answers with the inventory empty, and a second game is chosen by game', () => {
    const old = NEW.split('\n').filter(l => !l.includes('ev=inv') && !l.includes('ev=drill')).join('\n');
    const { s, f } = open(old + '\n' + old.replace(/hp=90/, 'hp=77'));
    const [a] = at(s, f, { pid: 3, t: 62 });
    assert.deepStrictEqual([a.hp, a.inv_t, a.inv, a.drill], [85, null, null, null]);
    const [b] = at(s, f, { pid: 3, t: 60, game: 2 });
    assert.strictEqual(b.hp, 77);
    s.db.close();
});
