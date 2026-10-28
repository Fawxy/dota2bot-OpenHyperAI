// Runs each test/test_*.lua in fengari (Lua 5.3 in JS) from the package dir; exits non-zero on failure.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const here = __dirname;
process.chdir(path.resolve(here, '..'));
const files = process.argv.length > 2
    ? process.argv.slice(2)
    : fs.readdirSync(here).filter(f => /^test_.*\.lua$/.test(f)).sort().map(f => path.join(here, f));

let failed = false;
for (const file of files) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    // TSTL targets Lua 5.1, which has a global unpack; fengari is 5.3.
    lauxlib.luaL_dostring(L, to_luastring('unpack = unpack or table.unpack\n'));
    console.log(`== ${path.basename(file)} (fengari)`);
    if (lauxlib.luaL_dofile(L, to_luastring(path.resolve(file))) !== 0) {
        console.error(lua.lua_tojsstring(L, -1));
        failed = true;
    }
}
process.exit(failed ? 1 : 0);
