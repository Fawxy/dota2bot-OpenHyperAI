// Offline harness: runs Lua test files in fengari (Lua 5.3 in JS) against stubbed Dota bot globals.
// Usage: node tests/humaniser/run.js [--jobs N] [test files...]   (defaults to every test_*.lua here)
// Each file runs in its own child process, N at a time (default 4): one process for the whole suite peaked at 1.6 GB,
// because fengari's garbage from every file stayed in one heap. Output is printed per file, in file order.
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const { newState, doFile, getGlobal } = require('./harness');

const here = __dirname;

/** Child mode: runs one file in this process; exits non-zero on failure. */
function runOne(file) {
    const L = newState();
    console.log(`== ${path.basename(file)}`);
    const err = doFile(L, file);
    if (err !== null) {
        console.error(err);
        process.exit(1);
    }
    if (!getGlobal(L, 'FINISHED')) {
        // A file that never calls finish() would print FAIL lines yet exit clean.
        console.error(`${path.basename(file)}: never called finish()`);
        process.exit(1);
    }
}

function runAll(files, jobs) {
    const results = new Array(files.length);
    let next = 0, printed = 0, failed = false;
    const flush = () => {
        while (printed < files.length && results[printed]) {
            const r = results[printed++];
            process.stdout.write(r.stdout);
            process.stderr.write(r.stderr);
            if (r.failed) failed = true;
        }
        if (printed === files.length) process.exit(failed ? 1 : 0);
    };
    const start = () => {
        if (next >= files.length) return;
        const i = next++;
        execFile(process.execPath, [__filename, '--one', files[i]], { maxBuffer: 1 << 28 }, (err, stdout, stderr) => {
            results[i] = { stdout, stderr: err && !stderr ? `${path.basename(files[i])}: ${err.message}\n` : stderr, failed: !!err };
            flush();
            start();
        });
    };
    for (let k = 0; k < Math.min(jobs, files.length); k++) start();
}

const args = process.argv.slice(2);
if (args[0] === '--one') {
    runOne(args[1]);
} else {
    let jobs = 4;
    const j = args.indexOf('--jobs');
    if (j >= 0) {
        jobs = Number(args[j + 1]);
        args.splice(j, 2);
        if (!(jobs >= 1)) {
            console.error('--jobs needs a number >= 1');
            process.exit(1);
        }
    }
    const files = args.length > 0 ? args.map(f => path.resolve(f)) : fs.readdirSync(here).filter(f => /^test_.*\.lua$/.test(f)).map(f => path.join(here, f));
    if (files.length === 0) process.exit(0);
    runAll(files, jobs);
}
