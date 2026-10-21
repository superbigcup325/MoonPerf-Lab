#!/bin/sh
# Build the Rust reference from a clean checkout. The command is part of the
# experiment: a different profile is a different implementation id.
set -eu
cd "$(dirname "$0")"
mkdir -p target
rustc --version
echo "rustc --edition 2021 -C opt-level=3 -C target-cpu=native -o target/hash-join main.rs"
exec rustc --edition 2021 -C opt-level=3 -C target-cpu=native -o target/hash-join main.rs
