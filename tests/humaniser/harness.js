// A fengari (Lua 5.3 in JS) state with the offline-test prelude: package.path at the repo root, a read-only io.open,
// a global unpack, HARNESS_DIR. Shared by run.js (test files) and fixtures.js (decision fixtures).
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

// Forward slashes: these paths are pasted into Lua strings, where Windows backslashes read as escapes.
const slash = p => p.split(path.sep).join('/');
const here = slash(__dirname);

/** `root` is the directory whose bots/ the Lua code is loaded from (default: this repo). */
function newState(root = path.resolve(__dirname, '../..')) {
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    // TSTL targets Lua 5.1, which has a global unpack; fengari is 5.3.
    // fengari has no io.open; tests that pin source text read files through this read-only shim.
    lua.lua_pushjsfunction(L, L => {
        const file = lua.lua_tojsstring(L, 1);
        if (!fs.existsSync(file)) return 0;
        // LF only: Windows checkouts (core.autocrlf) have CRLF, and source pins match on "\n".
        lua.lua_pushstring(L, to_luastring(fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n')));
        return 1;
    });
    lua.lua_setglobal(L, to_luastring('READ_FILE'));
    const ioShim = `if io.open == nil then io.open = function(p, m) if m ~= nil and m ~= "r" then return nil end local t = READ_FILE(p) if t == nil then return nil end return { read = function() return t end, close = function() end } end end\n`;
    const prelude = ioShim + `package.path = "${slash(root)}/?.lua;" .. package.path\nunpack = unpack or table.unpack\nHARNESS_DIR = "${here}"\nBOTS_ROOT = "${slash(root)}"\n`;
    lauxlib.luaL_dostring(L, to_luastring(prelude));
    return L;
}

/** Runs a Lua file; returns null or the error message. */
function doFile(L, file) {
    if (lauxlib.luaL_dofile(L, to_luastring(path.resolve(file))) !== 0) return lua.lua_tojsstring(L, -1);
    return null;
}

/** Runs a Lua chunk; returns null or the error message. */
function doString(L, src) {
    if (lauxlib.luaL_dostring(L, to_luastring(src)) !== 0) return lua.lua_tojsstring(L, -1);
    return null;
}

function getGlobal(L, name) {
    lua.lua_getglobal(L, to_luastring(name));
    const t = lua.lua_type(L, -1);
    const v = t === lua.LUA_TSTRING ? lua.lua_tojsstring(L, -1) : t === lua.LUA_TNIL ? null : lua.lua_toboolean(L, -1);
    lua.lua_pop(L, 1);
    return v;
}

module.exports = { newState, doFile, doString, getGlobal };
