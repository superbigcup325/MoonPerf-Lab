#!/bin/sh
set -eu
exec ./target/hash-join "$@"
