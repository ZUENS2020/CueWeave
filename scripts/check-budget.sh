#!/bin/sh
set -eu

phase=${1:-${CUEWEAVE_PHASE:-P0}}

case "$phase" in
    P0) production_limit=3200; test_limit=1200 ;;
    P1) production_limit=6200; test_limit=2000 ;;
    P2) production_limit=8500; test_limit=3000 ;;
    P3) production_limit=10500; test_limit=3800 ;;
    P4) production_limit=14000; test_limit=4500 ;;
    *) echo "unknown phase: $phase" >&2; exit 2 ;;
esac

for command_name in tokei jq cargo; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "required command is missing: $command_name" >&2
        exit 2
    fi
done

report=$(mktemp)
trap 'rm -f "$report"' EXIT HUP INT TERM

set -- crates
if [ -d apps ]; then
    set -- "$@" apps
fi
tokei --output json "$@" >"$report"

production=$(jq '[.[] | .reports[]? | select(.name | test("\\.(rs|swift|cs)$")) | select(.name | test("/(tests|Tests)/|/[^/]+\\.Tests/") | not) | .stats.code] | add // 0' "$report")
tests=$(jq '[.[] | .reports[]? | select(.name | test("\\.(rs|swift|cs)$")) | select(.name | test("/(tests|Tests)/|/[^/]+\\.Tests/")) | .stats.code] | add // 0' "$report")
oversized=$(jq -r '[.[] | .reports[]? | select(.name | test("\\.(rs|swift|cs)$")) | select(.stats.code > 600) | "\(.name): \(.stats.code)"] | .[]' "$report")
dependencies=$(cargo metadata --format-version 1 --no-deps | jq '[.packages[].dependencies[] | select(.kind == null or .kind == "normal") | select(.source != null) | .name] | unique | length')

printf '%s budget: production %s/%s, tests %s/%s, direct dependencies %s/12\n' \
    "$phase" "$production" "$production_limit" "$tests" "$test_limit" "$dependencies"

failed=0
if [ "$production" -gt "$production_limit" ]; then
    echo "production code exceeds the $phase budget" >&2
    failed=1
fi
if [ "$tests" -gt "$test_limit" ]; then
    echo "test code exceeds the $phase budget" >&2
    failed=1
fi
if [ "$dependencies" -gt 12 ]; then
    echo "direct production dependencies exceed the project budget" >&2
    failed=1
fi
if [ -n "$oversized" ]; then
    echo "source files over the 600 SLOC hard limit:" >&2
    echo "$oversized" >&2
    failed=1
fi

exit "$failed"
