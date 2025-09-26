#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv --ro-bind /etc/os-release /file

script='print(open("/file").read())'

# Test default args
python -c "$script" | grep -q 'VERSION'

# Test args passed via BWRAP_ARGS variable
export BWRAP_ARGS='--ro-bind /etc/passwd /file'
python -c "$script" | grep -q 'root:'

# User-bound paths take precedence
! VERBOSE=1 BWRAP_ARGS='--ro-bind / /' python -c '' | grep -q '/lib/'

printf '\n\n\n    ALL OK  ✅\n\n\n'
