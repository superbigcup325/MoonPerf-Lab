#!/bin/sh
set -eu
output=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$output" <<'JSON'
{"n": 16, "count_above": 4}
JSON
