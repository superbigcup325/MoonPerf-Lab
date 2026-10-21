#!/bin/sh
# Build the C implementation from a clean checkout. The command is part of the
# experiment: a different profile is a different implementation id.
set -eu
cd "$(dirname "$0")"
mkdir -p _build
cc --version | head -n 1
echo "cc -std=c17 -O3 -march=native -o _build/hash-join main.c"
exec cc -std=c17 -O3 -march=native -o _build/hash-join main.c
