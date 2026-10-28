#!/bin/sh
# Runs each test/test_*.lua under LuaJIT from the package dir; exits non-zero on failure.
cd "$(dirname "$0")/.." || exit 1
LUAJIT="${LUAJIT:-luajit}"
command -v "$LUAJIT" >/dev/null 2>&1 || { echo "luajit not found (set LUAJIT=...)" >&2; exit 1; }
status=0
for f in test/test_*.lua; do
    echo "== $(basename "$f") (luajit)"
    "$LUAJIT" "$f" || status=1
done
exit $status
