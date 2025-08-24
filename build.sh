#!/bin/sh
set -eu

cd "${0%/*}"
script_file="sandbox-venv.sh"
out="build/${script_file%.sh}"
{
    cat "$script_file"
    i=1
    for appendix in _wrapper_pip.sh _wrapper_exe.sh sitecustomize.py; do
        printf '\n\n'
        echo "# CUT HERE ------------------- Appendix $i: sandbox-venv $appendix script"
        cat "$appendix"
        i=$((i + 1))
    done
} > "$out"
chmod +x "$out"
echo "$out"
