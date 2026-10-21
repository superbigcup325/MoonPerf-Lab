#!/bin/sh
set -eu
exec ./_build/native/release/build/cmd/main/main.exe "$@"
