#!/bin/sh
# sandbox-venv: Secure container sandbox venv wrapper (GENERATED CODE)
# pip wrapper: Re-run sandbox-venv after every pip installation
set -u
# shellcheck disable=SC3040
case "$(set -o)" in *pipefail*) set -o pipefail ;; esac
alias realpath='realpath --no-symlinks'

venv="$(realpath "${0%/*}/..")"

_BWRAP_DEFAULT_ARGS=

# AUX_FUNCS: Auxiliary functions get inserted here

BWRAP_ARGS="$(split_args_by_lf "$_BWRAP_DEFAULT_ARGS")
--bind
$venv
$venv
$(split_args_by_lf "${BWRAP_ARGS-}")" \
    "$venv/bin/.unsafe_${0##*/}" "$@"
pip_return_status=$?

rm -f "$venv/cache/sandbox-venv.cache"

new_binaries="$(
    for file in "$venv/bin"/*; do
        [ -L "$file" ] || [ -d "$file" ] || [ ! -x "$file" ] ||
            [ "${file##*/}" = 'shell' ] ||
            is_already_wrapped "$file" ||
            is_python_shebang "$file" ||
            printf ' %s' "${file##*/}"
    done)"

if [ "$new_binaries" ]; then
    # Reset shebang to the one outside the sandbox
    for exe in $new_binaries; do sed -i "1s,/bin/.unsafe_,/bin/," "$venv/bin/$exe"; done

    if [ "$(command -v sandbox-venv)" ]; then
        echo "sandbox-venv: New binaries found:$new_binaries. Re-running sandbox-venv ..."
        sandbox-venv "$venv"
    else echo "WARNING: sandbox-venv not in \$PATH. Cannot sandbox/patch new executables:$new_binaries. Rerun sandbox-venv on this venv to stay secure."
    fi
fi

exit $pip_return_status
