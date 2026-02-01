#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv

cmd () { python -c '' 2>&1; }

cmd | grep -q 'Caching dependencies'  # First run caches
test -f .venv/sandbox/sandbox-venv.cache
cmd | grep -qv 'Caching dependencies'  # Second run uses the cache

