#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv --ro-bind /etc/os-release /file

script='print(open("/file").read())'

# Test default args
python -c "$script" | grep -q 'VERSION'
pip freeze

# Test args passed via BWRAP_ARGS variable
export BWRAP_ARGS='--ro-bind /etc/passwd /file'
python -c "$script" | grep -q 'root:'
pip freeze

printf '\n\n\n    ALL OK  ✅\n\n\n'
