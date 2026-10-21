#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p _build
cc --version | head -n 1
echo "cc -std=c17 -O3 -march=native -o _build/sql-groupby main.c"
exec cc -std=c17 -O3 -march=native -o _build/sql-groupby main.c
