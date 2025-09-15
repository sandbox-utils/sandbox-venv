#!/bin/sh
set -eu

. "${0%/*}/_init.sh"

sandbox-venv .venv

shell -c 'xdg-open "https://example.com"'
