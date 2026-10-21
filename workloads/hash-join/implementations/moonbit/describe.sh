#!/bin/sh
set -eu
toolchain=$(moon version 2>/dev/null | head -n 1)
compiler=$(moonc -v 2>/dev/null | head -n 1)
printf '{"toolchain": "%s / %s"}\n' "$toolchain" "$compiler"
