// Compiles every .lua file under `root` with the real LuaJIT (Dota's VM), when `luajit` is on PATH. The suite's fengari is Lua
// 5.3 and luaparse's LuaJIT mode is lenient: both accepted a statement after `break`, which LuaJIT refuses, and the module that
// held it (with everything requiring it) failed to load in game (slice pre-hit, prhchk1 04/11/2026).
// Returns { files, failures: [message] }, or undefined when luajit is not installed.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function luaFiles(p, out = []) {
    const s = fs.statSync(p);
    if (s.isDirectory()) for (const f of fs.readdirSync(p)) luaFiles(path.join(p, f), out);
    else if (p.endsWith('.lua')) out.push(p);
    return out;
}

function compileAll(root) {
    if (spawnSync('luajit', ['-v']).error) return undefined;
    const files = luaFiles(root);
    const list = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'luajit-')), 'files.txt');
    fs.writeFileSync(list, files.join('\n') + '\n');
    const code = 'for f in io.lines(os.getenv("LUAJIT_FILES")) do local ok, e = loadfile(f) if not ok then print(e) end end';
    const r = spawnSync('luajit', ['-e', code], { env: { ...process.env, LUAJIT_FILES: list }, encoding: 'utf8' });
    const failures = r.stdout.split('\n').filter(l => l.length > 0);
    if (r.status !== 0) failures.push(`luajit exited ${r.status}: ${r.stderr}`);
    return { files: files.length, failures };
}

module.exports = { compileAll };

if (require.main === module) {
    const r = compileAll(process.argv[2] || path.join(__dirname, '..', '..', 'bots'));
    if (r === undefined) {
        console.log('luajit not installed: skipped');
        process.exit(0);
    }
    for (const f of r.failures) console.log(f);
    console.log(`luajit compiled ${r.files} files, ${r.failures.length} failing`);
    process.exit(r.failures.length > 0 ? 1 : 0);
}
