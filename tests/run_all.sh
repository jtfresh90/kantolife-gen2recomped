#!/bin/sh
# tests/run_all.sh — run every *_test.lua with lua/luajit, report pass/fail.
# Usage: sh tests/run_all.sh   (from the mod root, or anywhere)
set -u
cd "$(dirname "$0")" || exit 2

LUA=""
for cand in lua lua5.1 luajit luajit-5.1; do
  if command -v "$cand" >/dev/null 2>&1; then LUA="$cand"; break; fi
done
if [ -z "$LUA" ] && [ -x "./.bin/lua" ]; then LUA="./.bin/lua"; fi
if [ -z "$LUA" ]; then
  echo "run_all.sh: no lua interpreter found (tried lua, lua5.1, luajit, ./.bin/lua)" >&2
  exit 2
fi
echo "Using interpreter: $LUA"

pass=0
fail=0
failed=""
for t in ./*_test.lua; do
  echo "--- $t ---"
  if "$LUA" "$t"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed="$failed $t"
  fi
done

echo "=== $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  echo "FAILED:$failed" >&2
  exit 1
fi
exit 0
