#!/usr/bin/env bash
# Runs every tests/test_*.gd headless and prints one line per test.
#
#   OK      test ran to completion and printed "TEST <NAME> OK"
#   FAIL    test ran to completion and printed "TEST <NAME> FAILED" or a "FAIL:" line
#   CRASH   Godot died (signal 11) before printing a verdict -- harness bug, not an assertion
#   SILENT  test ran to completion with no verdict token -- diagnostics, not assertions
#
# Diagnostics (test_spawn, test_collision, tools/audit_*.gd, tools/probe_*.gd) print
# measurements and have nothing to assert, so SILENT is the correct result for them.
#
# Usage: tools/run_tests.sh [name-filter]
GODOT=/mnt/c/Tools/Godot/Godot_v4.7.2-stable_mono_win64_console.exe
cd /mnt/c/Projects/Glyphwake || exit 1

filter="${1:-}"
pass=0; fail=0; crash=0; silent=0

for t in tests/test_*.gd; do
    name=$(basename "$t" .gd)
    [ -n "$filter" ] && case "$name" in *"$filter"*) ;; *) continue ;; esac

    out=$("$GODOT" --headless --path C:/Projects/Glyphwake --script "$t" 2>&1)
    code=$?

    if echo "$out" | grep -q "TEST .* OK"; then
        verdict="OK";     pass=$((pass+1))
    elif echo "$out" | grep -q "signal 11"; then
        verdict="CRASH";  crash=$((crash+1))
    elif echo "$out" | grep -qE "TEST .* FAILED|^FAIL:|FAIL: "; then
        verdict="FAIL";   fail=$((fail+1))
    else
        verdict="SILENT"; silent=$((silent+1))
    fi

    printf '%-6s %-24s exit=%s\n' "$verdict" "$name" "$code"
    # Surface the assertion text so a FAIL says why without a second run.
    if [ "$verdict" = FAIL ]; then
        echo "$out" | grep -E 'FAIL' | head -4 | sed 's/^/         /'
    fi
done

echo "----"
printf 'pass=%d fail=%d crash=%d silent=%d\n' "$pass" "$fail" "$crash" "$silent"
