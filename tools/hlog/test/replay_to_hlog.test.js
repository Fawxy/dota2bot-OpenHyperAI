'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { replayToHlog } = require('../replay_to_hlog');
const { parseLog } = require('../parse');

const row = (x, alive, deaths) => [x, 100, 500, 500, 1, alive, 3, 0, 600, 0, deaths, 0, 0, 0, 0, 2];

test('a replay becomes [HEV] bot and snap lines, with no snapshots while dead', () => {
    const nd = [
        { k: 'meta', players: [{ team: 2, heroId: 1 }, { team: 3, heroId: 2 }] },
        { k: 's', t: 0, p: [row(10, 1, 0), row(20, 1, 0)] },
        { k: 's', t: 1, p: [row(11, 0, 1), row(21, 1, 0)] },
        { k: 's', t: 2, p: [row(-99999, 0, 1), row(22, 1, 0)] },
        { k: 's', t: 3, p: [row(12, 1, 1), row(23, 1, 0)] },
    ].map(o => JSON.stringify(o)).join('\n');
    const heroes = { 1: { id: 1, name: 'npc_dota_hero_antimage' }, 2: { id: 2, name: 'npc_dota_hero_axe' } };
    const g = parseLog(replayToHlog(nd, heroes).join('\n'))[0];
    assert.strictEqual(g.bots[0].hero, 'antimage');
    assert.strictEqual(g.bots[1].team, 3);
    assert.deepStrictEqual(g.bots[0].snaps.map(s => s.t), [0, 3]);
    assert.strictEqual(g.bots[1].snaps.length, 4);
    assert.strictEqual(g.bots[0].snaps[1].deaths, 1);
});
