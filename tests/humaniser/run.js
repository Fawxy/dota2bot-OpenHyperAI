// Offline harness: runs Lua test files in fengari (Lua 5.3 in JS) against stubbed Dota bot globals.
// Usage: node tests/humaniser/run.js [test files...]   (defaults to every test_*.lua here)
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const here = __dirname;
const root = path.resolve(here, '../..');
const files = process.argv.length > 2 ? process.argv.slice(2) : fs.readdirSync(here).filter(f => /^test_.*\.lua$/.test(f)).map(f => path.join(here, f));

let failed = false;
for (const file of files) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    // TSTL targets Lua 5.1, which has a global unpack; fengari is 5.3.
    // fengari has no io.open; tests that pin source text read files through this read-only shim.
    lua.lua_pushjsfunction(L, L => {
        const file = lua.lua_tojsstring(L, 1);
        if (!fs.existsSync(file)) return 0;
        lua.lua_pushstring(L, to_luastring(fs.readFileSync(file, 'utf8')));
        return 1;
    });
    lua.lua_setglobal(L, to_luastring('READ_FILE'));
    const ioShim = `if io.open == nil then io.open = function(p, m) if m ~= nil and m ~= "r" then return nil end local t = READ_FILE(p) if t == nil then return nil end return { read = function() return t end, close = function() end } end end\n`;
    const prelude = ioShim + `package.path = "${root}/?.lua;" .. package.path\nunpack = unpack or table.unpack\nHARNESS_DIR = "${here}"\n`;
    lauxlib.luaL_dostring(L, to_luastring(prelude));
    console.log(`== ${path.basename(file)}`);
    if (lauxlib.luaL_dofile(L, to_luastring(path.resolve(file))) !== 0) {
        console.error(lua.lua_tojsstring(L, -1));
        failed = true;
    } else {
        // A file that never calls finish() would print FAIL lines yet exit clean.
        lua.lua_getglobal(L, to_luastring('FINISHED'));
        if (!lua.lua_toboolean(L, -1)) {
            console.error(`${path.basename(file)}: never called finish()`);
            failed = true;
        }
    }
}
process.exit(failed ? 1 : 0);
