#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv

shell -c 'echo >$HOME/foobar'
test -f .venv/home/foobar
