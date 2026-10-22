#!/bin/sh
# Measure a baseline campaign: N sequential runs of one workload, never in
# parallel, so the runs differ only by the host's own noise.
#
# Usage: scripts/measure-baseline.sh <workload> [runs]
#   OUT=results/tmp/baseline scripts/measure-baseline.sh numeric-scan 20
#
# Every run writes a normal artifact under $OUT/<workload>/run-NN/. The campaign
# is diagnostic data: it is not an artifact of record, and a committed baseline
# set is copied out of it explicitly.
#
# An adapter that needs a writable MoonBit registry (a sandbox whose `~/.moon`
# is read-only, for example) inherits MOON_HOME from the environment:
#   MOON_HOME=$PWD/.moon-home scripts/measure-baseline.sh sql-groupby 20
set -eu

PATH="${HOME}/.moon/bin:${PATH}"
export PATH
command -v moon >/dev/null 2>&1 || {
  echo "moon is not installed; see https://www.moonbitlang.com/download/" >&2
  exit 1
}

workload=${1:-}
runs=${2:-20}
if [ -z "$workload" ]; then
  echo "usage: scripts/measure-baseline.sh <workload> [runs]" >&2
  exit 2
fi

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "${OUT:-}" in
  "") out="$root/results/tmp/baseline" ;;
  /*) out=$OUT ;;
  *) out="$root/$OUT" ;;
esac
case "${DATA:-}" in
  "") data="$root/.data" ;;
  /*) data=$DATA ;;
  *) data="$root/$DATA" ;;
esac

if [ ! -f "$root/workloads/$workload/workload.toml" ]; then
  echo "unknown workload: $workload" >&2
  exit 1
fi

campaign="$out/$workload"
mkdir -p "$campaign"
log="$campaign/campaign.log"
: >"$log"

frequencies() {
  # Lowest and highest current core frequency, in kHz, when the kernel exposes
  # them; empty otherwise.
  low=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null |
    sort -n | sed -n '1p') || low=""
  high=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null |
    sort -n | tail -n 1) || high=""
  echo "${low:-?}..${high:-?}"
}

echo "# $workload, $runs sequential runs, $(date -u +%Y-%m-%dT%H:%M:%SZ)" |
  tee -a "$log"

index=0
while [ "$index" -lt "$runs" ]; do
  index=$((index + 1))
  target=$(printf '%s/run-%02d' "$campaign" "$index")
  printf 'run %d/%d  utc=%s  loadavg=%s  cpu_mhz=%s\n' \
    "$index" "$runs" "$(date -u +%H:%M:%SZ)" \
    "$(cut -d' ' -f1-3 /proc/loadavg)" "$(frequencies)" |
    tee -a "$log"
  # A stale artifact from an earlier attempt must not be counted as a second
  # run, so each run directory starts empty.
  rm -rf "$target"
  # A run that the harness rejects is part of the host's behaviour, not a
  # reason to throw the campaign away: record it and keep going. Anything else
  # (a missing binary, a build error) is a broken campaign and stops it.
  scratch="$campaign/run.log"
  status=0
  (
    cd "$root/moonperf"
    moon run cli --target native -- run "../workloads/$workload" \
      --out "$target" --data-dir "$data" --repo-root ..
  ) >"$scratch" 2>&1 || status=$?
  cat "$scratch" | tee -a "$log"
  if [ "$status" -ne 0 ]; then
    if grep -q 'experiment invalid' "$scratch"; then
      echo "run $index was rejected by the harness; continuing" |
        tee -a "$log"
    else
      echo "run $index failed to run; campaign stopped" | tee -a "$log"
      exit 1
    fi
  fi
  rm -f "$scratch"
done

echo "campaign complete: $campaign" | tee -a "$log"
