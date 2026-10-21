#!/bin/sh
# Reproduce the numeric-scan experiment with the MoonBit harness.
# Usage: scripts/reproduce-numeric-scan.sh
#   OUT=results/tmp/my-run DATA=.data scripts/reproduce-numeric-scan.sh
set -eu

PATH="${HOME}/.moon/bin:${PATH}"
export PATH
command -v moon >/dev/null 2>&1 || {
  echo "moon is not installed; see https://www.moonbitlang.com/download/" >&2
  exit 1
}

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${OUT:-results/tmp/repro}
data=${DATA:-.data}
case "$out" in
  /*) ;;
  *) out="$root/$out" ;;
esac
case "$data" in
  /*) ;;
  *) data="$root/$data" ;;
esac

cd "$root/moonperf"
exec moon run cli --target native -- run \
  ../workloads/numeric-scan \
  --out "$out" \
  --data-dir "$data" \
  --repo-root ..
