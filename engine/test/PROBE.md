# WP1 probe: TSTL generators as Lua coroutines

Date: 22/10/2026. Question: does TSTL compile `function*` / `yield*` into Lua that runs correctly offline
under fengari (Lua 5.3) and LuaJIT? **Answer: yes.**

## Toolchain
- typescript-to-lua 1.26.2 (typescript 5.5.4 via npm `overrides`; TSTL pins a 5.5.2 peer)
- `luaTarget: "5.1"`, `noImplicitSelf: true`, `luaBundle: "tasks.lua"` (outDir `dist`), `luaLibImport: "inline"`
- fengari 0.1.4 (reports `Lua 5.3`), LuaJIT 2.1.1792527110 (`/opt/homebrew/bin/luajit`)

`luaLibImport: "inline"` triggers a TSTL warning about possible duplicate lualib code across bundled
files. Today only `probe.ts` uses generator helpers, so there is no duplication, and the bundle is 214 lines
vs 2851 with `"require"` (which bundles the whole lualib). Revisit if several modules start using lualib helpers.

## What the generated Lua uses (`grep -c` on dist/tasks.lua)
| pattern | lines |
|---|---|
| `coroutine.create` | 1 |
| `coroutine.yield` | 10 |
| `__TS__Generator` | 7 |
| `__TS__DelegatedYield` | 3 |

Shape:
- `function*` becomes `__TS__Generator(function(...) ... end)`; calling it returns
  `{ ____coroutine = coroutine.create(...), next = generatorNext, [Symbol.iterator] = ... }`.
  From Lua, step with `gen:next()` (method call); it returns `{ value = ..., done = <coroutine dead> }`.
- `yield x` becomes a plain `coroutine.yield(x)`.
- `yield* g` becomes `__TS__DelegatedYield(g)`, which resumes `g.____coroutine` directly in a loop and
  re-yields each value, returning the inner generator's return value. So a 3-level chain is three nested
  coroutines; each frame's `outer:next()` resumes through all of them.
- `next()` on a dead coroutine returns `{ done = true }` (value nil). An error inside the body is re-raised
  from `next()` via `error(value, 0)`.
- Uses only `coroutine.create/resume/status/yield`, `select`, `setmetatable`, `ipairs`, `type`, and
  `table.unpack or unpack`. No `debug`, `load`, `string.dump`, or `goto`.
- The bundle defines a file-local `require` over an internal module table and ends with
  `return require("index", ...)`, so `dofile("dist/tasks.lua")` returns the module table
  (`Supported`, `Probe`). It only falls back to the global `require` for modules not in the bundle.

## Offline results (`npm test`)
```
checked 1 files, 0 with syntax errors

== test_probe.lua (fengari)
PCALL_YIELD [Lua 5.3]: ok
16 passed, 0 failed

== test_probe.lua (luajit)
PCALL_YIELD [LuaJIT 2.1.1792527110]: ok
16 passed, 0 failed
```
Asserted: `Supported()` is true; the 3-level `yield*` chain yields exactly 4 times then returns 30 with
`done=true`; `middle` alone returns 15 on its 4th step; local loop state persists across steps; two live
generators keep independent state; `next()` after completion stays `done=true`.

Mutation evidence: `middle` returning `v + 6` fails `outer return value` and `middle return value`;
`Supported()` returning false fails `Supported()`. Both make `npm test` exit 1.

## pcall-yield (documented, not asserted)
`Probe.yieldInPcall` calls `coroutine.yield()` inside an explicit `pcall(function() ... end)`.
- fengari (Lua 5.3): `PCALL_YIELD [Lua 5.3]: ok`
- LuaJIT 2.1: `PCALL_YIELD [LuaJIT 2.1.1792527110]: ok`

Both runtimes allow yielding across `pcall`. Stock PUC Lua 5.1 would raise
`attempt to yield across metamethod/C-call boundary`; Dota's VM is LuaJIT, so this is expected to work
in-game, but task bodies should still avoid it (and TS `try`/`catch`, which TSTL lowers to `pcall`)
until verified in Dota.

## In-game unknowns (check first)
OHA's integration will emit one line at load; these are the shapes to look for in the console log.

1. **`coroutine` is present in Dota's bot VM.** The `coroutine=` field is `type(coroutine)`.
   - Success: `[H:tasks] support coroutine=table bundle=ok`
   - Missing library (bundle loaded, but tasks cannot run; `Supported()` returns false):
     `[H:tasks] support coroutine=nil bundle=ok`
   - If the line shows `coroutine=table` but tasks still report `unsupported`, one of
     `create/resume/status/yield` is missing: `Supported()` checks all four.
2. **The luaBundle `require` shim works in the Dota VM.** The `bundle=` field is the outcome of loading
   `tasks.lua` (pcall'd by the integration).
   - Success: `bundle=ok` as above.
   - Failure: `[H:tasks] support coroutine=<type> bundle=fail <error message>`; a failure here means the
     file-local `require`/`____modules` table did not resolve (e.g. the VM rejects shadowing `require` or the
     chunk did not return the module table), and no task code is usable.
