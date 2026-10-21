#!/bin/sh
set -eu
output=""
repeat="1"
while [ $# -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --repeat) repeat="$2"; shift 2 ;;
    *) shift ;;
  esac
done
i=0
while [ "$i" -lt "$repeat" ]; do
  j=0
  while [ "$j" -lt 5000 ]; do
    j=$((j + 1))
  done
  i=$((i + 1))
done
cat > "$output" <<'JSON'
{"n": 16, "count_above": 5}
JSON
