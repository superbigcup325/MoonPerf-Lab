#!/bin/sh
set -eu
printf '{"toolchain": "rustc %s"}\n' "$(rustc --version | sed 's/^rustc //')"
