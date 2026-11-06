'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('../store');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const sql = fs.readFileSync(path.join(__dirname, '..', 'queries', 'stack_yield.sql'), 'utf8');

function run(lines) {
    const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-sy-')), 'a.log');
    const at = l => Number(l.match(/t=(\S+)/)[1]);
    fs.writeFileSync(f, [...lines].sort((x, y) => at(x) - at(y)).join('\n') + '\n');
    const s = new Store(':memory:');
    s.ingest(f);
    s.refreshViews();
    const out = s.query(sql, {});
    s.db.close();
    return out;
}

const pull = (pid, slot, res) => `pull_job pid=${pid} pos=5 lane=3 camp=1 slot=${slot} pk=full res=${res} why=${res === 'ok' ? 'ok' : 'cancelled:empty'}`;
const choice = (pid, slot, why) => `choice pid=${pid} kind=pull go=0 want=1 why=${why} src=own lane=3 slot=${slot}`;

test('stack_yield: what the pull did with each minute the stack gave it', () => {
    const out = run([
        line(0, 'bot pid=5 hero=h5 team=2 pos=5'),
        line(0, 'bot pid=6 hero=h6 team=2 pos=4'),
        // Minute 3: pid 5 yields and pulls the 3:46 spawn (ok); a pull slot before the yield (3:16) did not buy it.
        line(190, pull(5, 196, 'ok')),
        line(212, 'stack pid=5 min=3 res=skip why=lane'),
        line(221, pull(5, 226, 'ok')),
        // Minute 5: pid 5 yields; the pull is refused (hit, then enemy-site: the last counts); a pull 64 s on does not count.
        line(312, 'stack pid=5 min=5 res=skip why=lane'),
        line(314, choice(5, 316, 'hit')),
        line(344, choice(5, 346, 'enemy-site')),
        line(380, pull(5, 376, 'ok')),
        // Minute 7: pid 6 yields; its pull starts and fails. Another skip reason is not a yield.
        line(452, 'stack pid=6 min=7 res=skip why=lane'),
        line(460, pull(6, 466, 'fail')),
        line(452, 'stack pid=5 min=7 res=skip why=enemy-near'),
    ]);
    const by = Object.fromEntries(out.map(r => [r.why, r]));
    assert.strictEqual(by.all.n, 3);
    assert.strictEqual(by.all.started, 0.67);
    assert.strictEqual(by.all.ok, 0.33);
    assert.strictEqual(by.started.n, 2);
    assert.strictEqual(by['enemy-site'].n, 1);
    assert.strictEqual(by.hit, undefined);
});
