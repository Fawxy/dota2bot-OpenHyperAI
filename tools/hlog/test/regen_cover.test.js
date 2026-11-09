'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

// The coverage view counts a window for an item only when the item was in hand, the HP missing reached its full effect, nothing was
// already running and (a tango) a tree lay within 600, and says how many of those windows had the item's buff start inside.
test('regen_cover: a window counts for an item only when the item could have been used', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-regen-'));
    const f = path.join(dir, 'a.log');
    fs.writeFileSync(f, [
        '10/30 08:00:00 [HEV] t=-60 ev=bot pid=1 hero=lion team=2 schema=2 build=0123456',
        // counted for the tango, used
        '[HEV] t=100 ev=regen_win pid=1 mode=1 len=5 miss0=300 missmax=300 tg=2 sv=0 tge=112 sve=0 tree=250 under=0 used=tango',
        // counted for the tango, not used
        '[HEV] t=130 ev=regen_win pid=1 mode=1 len=4 miss0=200 missmax=250 tg=2 sv=0 tge=112 sve=0 tree=500 under=0 used=-',
        // tree too far: not counted for the tango
        '[HEV] t=160 ev=regen_win pid=1 mode=1 len=4 miss0=300 missmax=300 tg=2 sv=0 tge=112 sve=0 tree=900 under=0 used=-',
        // a retreat window: not the laning caller's place, not counted
        '[HEV] t=170 ev=regen_win pid=1 mode=4 len=4 miss0=300 missmax=300 tg=2 sv=0 tge=112 sve=0 tree=100 under=0 used=-',
        // buff already running: not counted
        '[HEV] t=190 ev=regen_win pid=1 mode=1 len=4 miss0=300 missmax=300 tg=2 sv=1 tge=112 sve=390 tree=100 under=1 used=-',
        // salve in hand, 400 missing against 390: counted for the salve, not used
        '[HEV] t=220 ev=regen_win pid=1 mode=1 len=4 miss0=400 missmax=400 tg=0 sv=1 tge=0 sve=390 tree=-1 under=0 used=-',
        // salve in hand, 200 missing against 390: not counted for the salve
        '[HEV] t=250 ev=regen_win pid=1 mode=1 len=4 miss0=200 missmax=200 tg=0 sv=1 tge=0 sve=390 tree=-1 under=0 used=-',
    ].join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const rows = s.query('SELECT item, windows, used_n, miss_share FROM regen_cover ORDER BY item').map(r => ({ ...r }));
    assert.deepStrictEqual(rows.map(r => [r.item, Number(r.windows), Number(r.used_n), Number(r.miss_share)]),
        [['salve', 1, 0, 1], ['tango', 2, 1, 0.5]]);
});
