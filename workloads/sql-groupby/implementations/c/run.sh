#!/bin/sh
set -eu
exec ./_build/sql-groupby "$@"
