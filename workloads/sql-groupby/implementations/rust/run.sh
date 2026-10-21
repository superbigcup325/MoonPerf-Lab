#!/bin/sh
set -eu
exec ./target/sql-groupby "$@"
