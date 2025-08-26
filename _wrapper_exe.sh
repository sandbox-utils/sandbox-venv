#!/bin/sh
# sandbox-venv: Secure container sandbox venv wrapper (GENERATED CODE)
set -eu
# shellcheck disable=SC3040
case "$(set -o)" in *pipefail*) set -o pipefail ;; esac
alias realpath='realpath --no-symlinks'
warn () { echo "sandbox-venv/wrapper: $*" >&2; }

venv="$(realpath "${0%/*}/..")"

# Quote args with spaces
format_args () {
    for arg in "$@"; do case "$arg" in
        $venv/*) printf "%s " "${venv##*/}/${arg#"$venv/"}" ;;
        *\ *) printf "'%s' " "$arg" ;;
        *) printf "%s " "$arg" ;;
    esac; done
}
formatted_cmdline="python $(format_args "$@")"

EXECUTABLE="${1:-/usr/bin/python3}"
_BWRAP_DEFAULT_ARGS=

[ -e "$venv/bin/python3" ]  # Assertion

# Expose these binaries
executables="
    /usr/bin/python3

    /usr/bin*/git
    /usr/bin/git-receive-*
    /usr/bin/git-upload-*

    /bin/bash
    /bin/env
    /bin/ls
    /bin/sh

    /bin/uname
    /sbin/ldconfig*
"

case $- in *x*) xtrace=-x ;; *) xtrace=+x ;; esac; set +x

# Collect binaries' lib dependencies
for dep in readelf ldd; do command -v "$dep" >/dev/null 2>&1 || { warn "Missing executable: $dep"; exit 1; }; done
lib_deps () {
    readelf -l "$1" >/dev/null 2>&1 || return 0  # Not a binary file
    readelf -l "$1" | awk '/interpreter/ {print $NF}' | tr -d '[]'
    ldd "$1" | awk '/=>/ { print $3 }' | { grep -E '^/' || true; }
}
collect="$executables"
for exe in $executables; do
    collect="$collect
        $(lib_deps "$exe")"
done

# Collect lib deps from venv/lib/*.so
root_so_lib_dirs="
    /usr/lib/python3*/lib-dynload
    /usr/lib64/python3*/lib-dynload"
# XXX: If some `git` tools are failing, add $(find /usr/lib/git-core -type f)
for exe in $(find "$venv/lib" $root_so_lib_dirs -name '*.so' 2>/dev/null || true); do
    collect="$collect
        $(lib_deps "$exe")"
done

# Explicit Python deps we know of
py_libs="
    /usr/include/python3*
    /usr/lib/python3*
    /usr/lib64/python3*
    /usr/local/lib/python3*
"
seccomp_libs="
    /usr/lib/python3*/*/seccomp.*.so
    /usr/lib/*/libseccomp.so*
    /usr/lib64/libseccomp.so*
"
git_libs="
    /usr/lib*/git-core
"
ro_bind_extra="
    /etc/hosts
    /etc/resolv.conf

    /etc/ld.so.cache
    /etc/os-release
    /usr/share/locale
    /usr/share/zoneinfo

    /usr/share/ca-certificates*
    /etc/pki*
    /etc/ssl
    /usr/share/pki*
"

collect="
    $collect
    $ro_bind_extra
    $seccomp_libs
    $git_libs
    $py_libs"

# Filter collect, warn on non-existant paths, unique sort, cull.
# Use separate for-loop to expand globstar.
prev="sandbox@"
collect="$(
    # Split only on newline
    for path in $collect; do
        path="$(printf '%s' "$path" | sed -r 's/^ +//;s/ +$//')"
        [ -e "$path" ] ||
            # Don't warn for globstar paths as they are allowed to not match
            case "$path" in *\**) continue ;; *) warn "Warning: missing $path"; continue ;; esac
        echo "$path"
    done |
    sort -u |
    # If collected paths contain /foo/ and /foo/bar,
    # keep only /foo since it covers both
    while IFS= read -r path; do
        case $path in "$prev"/*) continue;; esac
        echo "$path"; prev="$path"
    done)"

split_args_by_lf () {
    lf='
'
    printf '%s' "$1" | case "$1" in *$lf*) cat ;; *) tr ' ' '\n' ;; esac; }

# Begins constructing args for bwrap, in reverse
# (later args in command line override prior ones)
IFS='
'  # Split args only on newline
# shellcheck disable=SC2046
set -- $(split_args_by_lf "$_BWRAP_DEFAULT_ARGS") \
       $(split_args_by_lf "${BWRAP_ARGS:-}") \
       "${0%/*}/$EXECUTABLE" "$@"

for path in $collect; do set -- --ro-bind "$path" "$path" "$@"; done

# RW-bind project dir (dir that contains .venv)
# but RO-bind some dirs like .venv and git
proj_dir="$(realpath "$venv/..")"
ro_bind_pwd_extra="
    ${venv##*/}
    .git"
for path in $ro_bind_pwd_extra; do
    [ ! -e "$proj_dir/$path" ] || set -- --ro-bind "$proj_dir/$path" "$proj_dir/$path" "$@"
done
set -- --bind "$proj_dir" "$proj_dir" "$@"

# RW bind cache dirs for downloads etc.
home="${HOME:-"/home/$USER"}"
pip_cache="$home/${XDG_CACHE_HOME:-.cache}/pip"
mkdir -p "$venv/cache" "$pip_cache"
[ ! "${SANDBOX_USE_PIP_CACHE-}" ] || {
    mkdir -p "$venv/cache/pip" &&
        echo "This dir is an artefact of Bubblewrap bind mounting. Real pip cache is in \$HOME/.cache/pip" \
        > "$venv/cache/pip/note.txt"
    set -- --bind "$pip_cache" "$home/.cache/pip" "$@"
}
set -- --bind "$venv/cache" "$home/.cache" "$@"

# Pass our own redacted copy of env
for var in $(env | grep -E '^(USER|LOGNAME|UID|PATH|TERM|LANGUAGE|LANG|LC_.*?|HOSTNAME)='); do
    set -- --setenv "${var%%=*}" "${var#*=}" "$@"
done

set $xtrace

warn "exec bwrap [...] $formatted_cmdline"

uid="$(id -u)"
cwd="$(pwd)"

[ ! "${VERBOSE:-${verbose:-}}" ] || set -x

# shellcheck disable=SC2086
exec bwrap \
    --dir /tmp \
    --dir "/run/user/$uid" \
    --dir "$cwd" \
    --chdir "$cwd" \
    --proc /proc \
    --dev /dev \
    --clearenv \
    --unshare-all \
    --share-net \
    --new-session \
    --die-with-parent \
    --setenv PS1 '\u @ \h \$ ' \
    --setenv HOME "$home" \
    --setenv USER "user" \
    --setenv VIRTUAL_ENV "$venv" \
    --setenv PYTHONPATH "$venv/sandbox:${PYTHONPATH-}" \
    "$@"
