// Offline test of bots/FunLib/stock_log.lua: named cases, parity with our fork's telemetry on random worlds, and the
// bot/snap lines unchanged from the previous logger. Runs in the fork's harness (fengari stubs):
//   node tests/stock_log/run.js <team-bots checkout> [<previous stock_log.lua>]
// The previous logger defaults to `git show 05f319cc:bots/FunLib/stock_log.lua` (before the ledger events).
const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');

const fwd = (p) => path.resolve(p).split(path.sep).join('/');
const [root, oldArg] = process.argv.slice(2);
if (!root) {
    console.error('usage: node tests/stock_log/run.js <team-bots checkout> [<previous stock_log.lua>]');
    process.exit(2);
}
let old = oldArg;
if (!old) {
    old = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'stock-log-')), 'stock_log_old.lua');
    fs.writeFileSync(old, execFileSync('git', ['show', '05f319cc:bots/FunLib/stock_log.lua'], { cwd: __dirname }));
}
const { newState, doString, doFile } = require(path.resolve(root, 'tests/humaniser/harness'));
const L = newState(path.resolve(root));
doString(L, `STOCK_FILE = "${fwd(path.join(__dirname, '../../bots/FunLib/stock_log.lua'))}" OLD_FILE = "${fwd(old)}"`);
const err = doFile(L, path.join(__dirname, 'test_stock_log.lua'));
if (err) {
    console.error(err);
    process.exit(1);
}
