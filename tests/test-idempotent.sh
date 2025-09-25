#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv
sandbox-venv .venv --setenv FOOBAR 1

VERBOSE=1 shell -c 'echo' 2>&1 1>/dev/null |
    grep -q -e '--setenv FOOBAR'
