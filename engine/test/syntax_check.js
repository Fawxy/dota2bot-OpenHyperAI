// Parses every .lua file under the given paths as LuaJIT (Dota's dialect) and reports syntax errors.
const fs = require('fs'), path = require('path'), luaparse = require('luaparse');
let files = [], bad = 0;
function walk(p) {
    const s = fs.statSync(p);
    if (s.isDirectory()) for (const f of fs.readdirSync(p)) walk(path.join(p, f));
    else if (p.endsWith('.lua')) files.push(p);
}
const roots = process.argv.slice(2);
if (roots.length === 0) { console.error('usage: node test/syntax_check.js <path...>'); process.exit(2); }
roots.forEach(walk);
for (const f of files) {
    // luaparse rejects `break;`, which is valid Lua; normalise it.
    try { luaparse.parse(fs.readFileSync(f, 'utf8').replace(/\bbreak\s*;/g, 'break '), { luaVersion: 'LuaJIT', comments: false }); }
    catch (e) { bad++; console.log(`${f}: ${e.message}`); }
}
console.log(`checked ${files.length} files, ${bad} with syntax errors`);
process.exit(bad || files.length === 0 ? 1 : 0);
