#!/bin/sh
# Vendors the built bundle into a temp dir and checks the output, manifest-based cleanup and type-checking.
cd "$(dirname "$0")/.." || exit 1
LUAJIT="${LUAJIT:-luajit}"
PKG="$(pwd)"
TMP="$(mktemp -d)"
STASH="$(mktemp -d)"
LUA="$TMP/bots/FunLib/sdk/tasks"
TYPES="$TMP/typescript/bots/FunLib/sdk/tasks"
passed=0
failed=0
restore() {
    [ -f "$STASH/support.d.ts" ] && mv "$STASH/support.d.ts" dist/types/support.d.ts
    rm -rf "$TMP" "$STASH"
}
trap restore EXIT

check() {
    name="$1"; shift
    if "$@" >/dev/null 2>&1 </dev/null; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL: $name"; fi
}

vendor() { node scripts/vendor.js --lua "$LUA" --types "$TYPES" >/dev/null; }

echo "== test_vendor.sh"

mkdir -p "$LUA" "$TYPES/decl"
echo "keep me" > "$LUA/unrelated.lua"
echo "keep me" > "$TYPES/decl/unrelated.d.ts"

check "vendor refuses without --types" sh -c '! node scripts/vendor.js --lua "$1"' _ "$LUA"
check "vendor run 1" vendor

SHA="$(git rev-parse HEAD)"
check "tasks.lua header" sh -c 'head -n 1 "$1" | grep -Eq "^-- Vendored from dota-bot-sdk packages/lua-tasks @ $2(-dirty)?\. Do not edit; run npm run vendor\.$"' _ "$LUA/tasks.lua" "$SHA"
check "tasks.lua body is the bundle" sh -c 'tail -n +2 "$1" | cmp -s - dist/tasks.lua' _ "$LUA/tasks.lua"
check "VERSION commit" grep -Eq "^commit: $SHA(-dirty)?$" "$LUA/VERSION"
check "VERSION build date" grep -Eq '^built: [0-9]{2}/[0-9]{2}/[0-9]{4} ' "$LUA/VERSION"
check "tasks.d.ts re-exports decl" grep -q 'export \* from "./decl/index";' "$TYPES/tasks.d.ts"
check "decl/index.d.ts copied" cmp -s dist/types/index.d.ts "$TYPES/decl/index.d.ts"
check "no test-only declarations" sh -c '! ls "$1"/decl | grep -Eq "testing|probe|test_entry"' _ "$TYPES"
# `luajit -e ... file` runs `file` as the script (arg[1] would be nil and dofile(nil) reads stdin), so pass the path via env.
check "vendored bundle loads with public API only" env TASKS_LUA="$LUA/tasks.lua" "$LUAJIT" -e 'local t=dofile(os.getenv("TASKS_LUA")); assert(type(t.Tasks.Step)=="function" and type(t.Verbs.walkTo)=="function" and t.Testing==nil and t.Probe==nil)'
check "assertion above can fail (test bundle exposes Testing)" sh -c '! env TASKS_LUA=dist/tasks_test.lua "$1" -e '"'"'local t=dofile(os.getenv("TASKS_LUA")); assert(t.Testing==nil)'"'"'' _ "$LUAJIT"

# A consumer importing the vendored path the way OHA does must type-check against the declarations.
mkdir -p "$TMP/typescript/consumer"
cat > "$TMP/typescript/consumer/use.ts" <<'TS'
import * as LuaTasks from "bots/FunLib/sdk/tasks/tasks";

export function start(bot: LuaTasks.TaskUnit, adapter: LuaTasks.Adapter): boolean {
    LuaTasks.init(adapter);
    if (!LuaTasks.Supported()) return false;
    return LuaTasks.Tasks.task(bot, { name: "walk", host: 1 }, function* () {
        const r: LuaTasks.Result = yield* LuaTasks.Verbs.walkTo(bot, { x: 1, y: 2 });
        return r;
    });
}
TS
cat > "$TMP/typescript/tsconfig.json" <<JSON
{
  "compilerOptions": {
    "lib": ["ES2020"], "target": "ES2020", "module": "CommonJS", "moduleResolution": "Node",
    "strict": true, "noEmit": true, "baseUrl": ".",
    "typeRoots": ["$PKG/node_modules"],
    "types": ["@typescript-to-lua/language-extensions", "lua-types/5.1"]
  },
  "files": ["consumer/use.ts"]
}
JSON
check "consumer type-checks against vendored declarations" npx --no-install tsc -p "$TMP/typescript/tsconfig.json"

# Stale cleanup: drop a declaration from dist and re-vendor; only the stale vendored copy goes.
mv dist/types/support.d.ts "$STASH/support.d.ts"
check "vendor run 2" vendor
check "stale vendored declaration removed" test ! -e "$TYPES/decl/support.d.ts"
check "other vendored declarations kept" test -f "$TYPES/decl/index.d.ts"
check "manifest no longer lists it" sh -c '! grep -q "support.d.ts" "$1"' _ "$LUA/.vendored"
check "unrelated lua file survives" grep -q "keep me" "$LUA/unrelated.lua"
check "unrelated types file survives" grep -q "keep me" "$TYPES/decl/unrelated.d.ts"
mv "$STASH/support.d.ts" dist/types/support.d.ts

mv dist/tasks.lua "$STASH/tasks.lua"
out="$(node scripts/vendor.js --lua "$LUA" --types "$TYPES" 2>&1)"
code=$?
mv "$STASH/tasks.lua" dist/tasks.lua
check "missing bundle fails" test "$code" -ne 0
check "missing bundle message" sh -c 'printf "%s" "$1" | grep -q "dist/tasks.lua is missing; run npm run build first"' _ "$out"
check "missing bundle leaves previous vendor intact" test -f "$LUA/tasks.lua"

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
