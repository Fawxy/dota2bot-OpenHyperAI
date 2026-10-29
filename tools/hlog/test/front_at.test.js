'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const LOG = [
    '[VScript] [HEV] t=-90.000 ev=bot pid=0 hero=luna team=2 schema=2 build=abc pos=1',
    '[VScript] [HEV] t=60.000 ev=front team=2 top=0.250 topx=-3500 topy=5000 mid=0.400 midx=-1400 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=60.000 ev=front team=3 top=0.500 topx=0 topy=5000 mid=0.700 midx=2800 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=60.000 ev=snap pid=0 x=0 y=4900 alive=1 hp=100 ln=top s=0.500 ld=100',
    '[VScript] [HEV] t=61.000 ev=front team=2 top=0.300 topx=-2800 topy=5000 mid=0.400 midx=-1400 midy=0 bot=0.500 botx=0 boty=-5000',
    '[VScript] [HEV] t=120.000 ev=snap pid=0 x=10 y=4900 alive=1 hp=100 ln=top s=0.510 ld=100',
].join('\n');

const QUERY = fs.readFileSync(path.join(__dirname, '../queries/front_at.sql'), 'utf8');

function store(text) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-front-')), 'a.log');
    fs.writeFileSync(f, text + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    return { s, f };
}

const at = (s, file, t, game) => s.query(QUERY, { file, game: game ?? null, t }).map(r => ({ ...r }));

test('front_at: latest ev=front per team and ev=snap per hero at or before each clock', () => {
    const { s, f } = store(LOG);
    const a = at(s, f, 60);
    const front = (rows, team) => rows.find(r => r.kind === 'front' && r.who === team);
    assert.strictEqual(front(a, 2).top, 0.25);
    assert.strictEqual(front(a, 3).mid, 0.7);
    assert.deepStrictEqual(a.filter(r => r.kind === 'hero').map(h => [h.hero, h.ln, h.s]), [['luna', 'top', 0.5]]);
    const b = at(s, f, 90);
    assert.strictEqual(front(b, 2).top, 0.3, 'the later line wins');
    assert.strictEqual(front(b, 2).t, 61);
    assert.strictEqual(b.find(r => r.kind === 'hero').t, 60, 'snaps after the clock are ignored');
    assert.deepStrictEqual(at(s, f, 30), []);
    s.db.close();
});

test('front_at: a log with two games reads one game at a time', () => {
    const { s, f } = store(LOG + '\n' + LOG.replace(/top=0\.250/, 'top=0.111'));
    const top = game => at(s, f, 60, game).find(r => r.kind === 'front' && r.who === 2)?.top;
    assert.strictEqual(top(1), 0.25);
    assert.strictEqual(top(2), 0.111);
    assert.deepStrictEqual(at(s, f, 60, 3), []);
    s.db.close();
});

test('front_at: a human hero is named from ev=player, and the later of ev=bot / ev=player wins', () => {
    const text = [
        '[HEV] t=-90 ev=player pid=5 hero=axe team=3 human=1',
        '[HEV] t=-90 ev=bot pid=0 hero=luna team=2 schema=2 build=abc pos=1',
        '[HEV] t=60 ev=snap pid=5 x=0 y=0 alive=1 hp=100 ln=bot s=0.4 ld=10',
        '[HEV] t=60 ev=snap pid=0 x=0 y=0 alive=1 hp=100 ln=top s=0.5 ld=10',
    ].join('\n');
    const { s, f } = store(text);
    const heroes = at(s, f, 60).filter(r => r.kind === 'hero').map(r => [r.who, r.hero]);
    assert.deepStrictEqual(heroes, [[0, 'luna'], [5, 'axe']]);
    s.db.close();
});
