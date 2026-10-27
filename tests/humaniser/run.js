// Offline harness: runs Lua test files in fengari (Lua 5.3 in JS) against stubbed Dota bot globals.
// Usage: node tests/humaniser/run.js [test files...]   (defaults to every test_*.lua here)
const fs = require('fs');
const path = require('path');
const { newState, doFile, getGlobal } = require('./harness');

const here = __dirname;
const files = process.argv.length > 2 ? process.argv.slice(2) : fs.readdirSync(here).filter(f => /^test_.*\.lua$/.test(f)).map(f => path.join(here, f));

let failed = false;
for (const file of files) {
    const L = newState();
    console.log(`== ${path.basename(file)}`);
    const err = doFile(L, file);
    if (err !== null) {
        console.error(err);
        failed = true;
    } else if (!getGlobal(L, 'FINISHED')) {
        // A file that never calls finish() would print FAIL lines yet exit clean.
        console.error(`${path.basename(file)}: never called finish()`);
        failed = true;
    }
}
process.exit(failed ? 1 : 0);
