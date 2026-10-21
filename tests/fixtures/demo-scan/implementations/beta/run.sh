#!/bin/sh
set -eu
output=""
repeat=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --repeat) repeat="$2"; shift 2 ;;
    *) shift ;;
  esac
done
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$repeat" = "0" ]; then
  :
elif [ -f "$dir/calls" ]; then
  sleep 2
else
  : > "$dir/calls"
fi
cat > "$output" <<'JSON'
{"n": 16, "count_above": 5}
JSON
