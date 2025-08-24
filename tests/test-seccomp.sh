#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv

pip install pyseccomp

assert_have_seccomp () { "$@" 2>&1 | grep -q 'sandbox-venv/seccomp: allowing'; }

strace -f --string-limit=255 --verbose=all python -vvv -c 'import os'

printf '\n\n\n    ALL OK  ✅\n\n\n'
