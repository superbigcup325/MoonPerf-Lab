#!/bin/sh
set -eu
printf '{"toolchain": "cc %s"}\n' "$(cc --version | head -n 1 | sed 's/^[^ ]* //')"
