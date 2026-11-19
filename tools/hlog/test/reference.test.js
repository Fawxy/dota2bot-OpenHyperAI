'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { strip, logsOf } = require('../reference');
const { parseLog } = require('../parse');

const WHO = ['/Users/someone', 'someone'];
const CONSOLE = [
    '11/19 21:13:25 LoadScript: /Users/someone/Library/Steam/bots/hero_selection.lua, scope name HeroSelectionScriptScope',
    '11/19 21:14:27 [DOTACTL] ev=start worktree=oha-x mode=bots human=none timescale=8 seed=30 set="Ours.Team=radiant"',
    '11/19 21:14:28 However, we did find a player for playerID 10 with steamID [U:1:12345678].',
    '11/19 21:14:29 [VScript] [Humaniser] pid=5 dragon_knight allyOfHuman=false skill=1',
    '11/19 21:14:30 [VScript] [HEV] t=1.000 ev=snap pid=5 x=10 y=20 lvl=1 xpn=250',
    '11/19 21:14:31 [VScript] [HEV] t=2.000 ev=bot pid=5 hero=dragon_knight team=3 build=74b32498',
    "11/19 21:14:32 [VScript] ...bots/mode_laning_generic.lua:12: attempt to index a nil value (local 'bot')",
    '11/19 21:18:09 [Networking] Summary of connection [#1 UDP steamid:76561198000000000@127.0.0.1:49229 \'someone\']:',
];

test('a stripped log drops the console lines that name the user and parses to the same games', () => {
    const text = CONSOLE.join('\n') + '\n';
    const out = strip(text, WHO);
    assert.doesNotMatch(out, /someone|steamid|U:1:/i);
    assert.match(out, /\[DOTACTL\] ev=start/);
    assert.deepStrictEqual(parseLog(out), parseLog(text));
    assert.strictEqual(parseLog(out)[0].errors.length, 1);
});

test('a line the store reads that names the user stops the strip: a stack trace through the home folder, a Steam id in telemetry', () => {
    assert.throws(() => strip('11/19 21:14:32 [VScript] /Users/someone/dota/bots/x.lua:12: attempt to index a nil value\n', WHO), /names the user \(\/Users\/someone\)/);
    assert.throws(() => strip('11/19 21:14:30 [VScript] [HEV] t=1.000 ev=mark by=76561198000000000 text=hi\n', WHO), /names the user/);
});

test("a run's logs are its label prefix only: h2h742 takes neither h2h742-first nor h2h742m", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ref-test-'));
    for (const f of ['2026-11-19T08-18-17-h2h742_A_rad_1.log', '2026-11-19T08-08-22-h2h742-first_A_rad_1.log', '2026-11-19T08-18-17-h2h742m_A_rad_1.log', '2026-11-19T08-18-17-h2h742_A_rad_1.dem']) fs.writeFileSync(path.join(dir, f), '');
    assert.deepStrictEqual(logsOf('h2h742', dir), ['2026-11-19T08-18-17-h2h742_A_rad_1.log']);
    fs.rmSync(dir, { recursive: true });
});
