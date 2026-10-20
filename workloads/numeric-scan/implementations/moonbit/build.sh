#!/bin/sh
# Build the MoonBit implementation from a clean checkout. The binary lands in
# _build/ inside this directory (git-ignored), as the toolchain decides.
set -eu
cd "$(dirname "$0")"
exec moon build --target native --release
