#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec moon build --target native --release
