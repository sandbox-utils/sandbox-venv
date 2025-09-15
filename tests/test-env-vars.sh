#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv

FOOBAR=1 shell -c 'set -u; echo $FOOBAR'
FOOBAR=1 python -c 'import os; os.environ["FOOBAR"]'
python -c 'import os; os.environ["PWD"]'
! python -c 'import os; os.environ["NONEXISTENT"]' 2>/dev/null
