#!/usr/bin/env bash
# Run all tests in the witch-line test suite.
# Usage: bash tests/run.sh [pattern]
#   pattern: optional glob pattern to filter test files (e.g., "unit", "integration")

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NVIM="${NVIM:-nvim}"
FAILURES=0
PASSED=0

# Determine which test files to run
if [[ -n "${1:-}" ]]; then
    FILES=$(find "$PLUGIN_ROOT/tests" -name "*_spec.lua" -path "*$1*" | sort)
else
    FILES=$(find "$PLUGIN_ROOT/tests" -name "*_spec.lua" | sort)
fi

if [[ -z "$FILES" ]]; then
    echo "No test files found matching pattern: ${1:-*}"
    exit 1
fi

echo "========================================"
echo "  Witch-Line Test Suite"
echo "  Plugin root: $PLUGIN_ROOT"
echo "========================================"
echo ""

for f in $FILES; do
    rel="${f#$PLUGIN_ROOT/}"
    printf "  %-50s" "$rel"
    OUTPUT=$("$NVIM" --headless --cmd "set rtp+=$PLUGIN_ROOT" -c "luafile $f" -c "qa!" 2>&1) || true
    EXIT_CODE=${PIPESTATUS[0]:-$?}
    if echo "$OUTPUT" | grep -qE "^[0-9]+/[0-9]+ passed, 0 failed"; then
        PASS_LINE=$(echo "$OUTPUT" | grep -E "^[0-9]+/[0-9]+ passed" || true)
        echo "PASS  ($PASS_LINE)"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL"
        echo "$OUTPUT" | tail -15 | sed 's/^/    /'
        FAILURES=$((FAILURES + 1))
    fi
done

echo ""
echo "========================================"
echo "  Results: $PASSED passed, $FAILURES failed"
echo "========================================"

exit $FAILURES
