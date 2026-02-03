#!/bin/sh
# sandbox-venv: Secure container sandbox venv wrapper (GENERATED CODE)
set -eu
# shellcheck disable=SC3040
case "$(set -o)" in *pipefail*) set -o pipefail ;; esac
alias realpath='realpath --no-symlinks'
warn () { echo "sandbox-venv/wrapper: $*" >&2; }
command_exists () { command -v "$1" >/dev/null 2>&1; }

venv="$(realpath "${0%/*}/..")"
proj_dir="$(realpath "$venv/..")"

# Quote args with spaces. Do this here before overriding "$@"
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
    /usr/bin/python
    /usr/bin/python3
    /usr/bin/python3*

    /usr/bin*/git
    /usr/bin/git-receive-*
    /usr/bin/git-upload-*

    /bin/bash
    /bin/env
    /bin/ls
    /bin/sh
    /bin/cat
    /bin/stat
    /usr/bin/realpath

    /bin/uname
    /sbin/ldconfig*
"
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
    /etc/alternatives

    /etc/ld.so.*
    /etc/os-release
    /usr/share/locale
    /usr/share/i18n
    /usr/share/zoneinfo
    /usr/share/terminfo
    /etc/localtime
    /etc/timezone

    /usr/share/ca-certificates*
    /etc/pki*
    /etc/ssl
    /usr/share/pki*
"

# Begin constructing args for bwrap, in reverse
# (later args in command line override prior ones)

split_args_by_lf () {
    lf='
'
    printf '%s' "$1" | case "$1" in *$lf*) cat ;; *) tr ' ' '\n' ;; esac
}

# Support BWRAP_ARGS passed to the process as well as via .env file
prev_BWRAP_ARGS="${BWRAP_ARGS:-}"
# Init env from dotenv file
# shellcheck disable=SC2046
[ ! -e "$proj_dir/.env" ] || { . "$proj_dir/.env"; export $(grep -Pzo '(?m)^\w*(?==)' "$proj_dir/.env" | tr '\0' '\n'); }
IFS='
'  # Split args only on newline
_USER_ARGS="$(split_args_by_lf "$_BWRAP_DEFAULT_ARGS")
$(split_args_by_lf "${prev_BWRAP_ARGS:-}")
$(split_args_by_lf "${BWRAP_ARGS:-}")"
paths_from_args=$(
    set -f; IFS='
'
    # shellcheck disable=SC2086
    set -- $_USER_ARGS
    while [ $# -gt 0 ]; do
        case "$1" in --*bind*) echo "$2" ;; esac
        shift
    done
)
# shellcheck disable=SC2086
set -- $_USER_ARGS "${0%/*}/$EXECUTABLE" "$@"
unset IFS

# Make private temp dir for use as TMPDIR
uid="$(id -u)"
tmpdir="$(mktemp -d -t ".sandbox-venv.$uid.$$.XXXXXX")"
cleanup_temp () { [ -z "$(find "$tmpdir" -type f -print -quit)" ] && rm -r "$tmpdir"; }
trap cleanup_temp EXIT

# Support for Open URLs / XDG Desktop Portal in wrapped applications
if command_exists xdg-dbus-proxy; then
    dbus_proxy_path="$tmpdir/dbus-proxy"
    fifo_path="${dbus_proxy_path}.sync"
    mkfifo "$fifo_path"

    xdg-dbus-proxy --fd=8 8>"$fifo_path" \
        "${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR:-/run/user/$uid}/bus}" \
        "$dbus_proxy_path" --filter --talk=org.freedesktop.portal.* \
        &

    # Unblock FIFO and wait for xdg-dbus-proxy to touch $dbus_proxy_path
    exec 7<"$fifo_path" && rm "$fifo_path" && sleep .1 && test -e "$dbus_proxy_path"

    add_dbus_send () {
        for exe in dbus-send gdbus busctl; do
            if command_exists "$exe"; then
                executables="$executables
$(command -v "$exe")"
                return 0
            fi
        done
        return 1
    }
    add_dbus_send || warn 'Need one of dbus-send (from package dbus-bin) / gdbus (libglib*-bin) / busctl (systemd) to use XDG Desktop Portal'

    exec 9<<EOF
#!/bin/sh
set -eu
address="unix:path=$dbus_proxy_path"
pth='/org/freedesktop/portal/desktop'
service='org.freedesktop.portal.Desktop'
interface='org.freedesktop.portal.OpenURI'
method='OpenURI'
gdbus call --address "\$address" --dest \$service --object-path \$pth --method \$interface.\$method \
    '' "\$1" '{}' >/dev/null \
||
busctl --verbose --address "\$address" call \$service \$pth \$interface \$method \
    'ssa{sv}' '' "\$1" 0 \
||
dbus-send --bus="\$address" --type method_call --dest=\$service \$pth \$interface.\$method \
    string: string:"\$1" dict:string:variant:
EOF
    exec 6<<EOF
[Instance]
flatpak-version=9000
EOF
    xdg_open='/usr/bin/xdg-open'
    # Extra bwrap args
    # FIXME: Implementation is BUGGY. Even as appropriate mounts are bound,
    #   a full working XDG Portal (e.g. a working file chooser FUSE mount)
    #   was so far in testing of some PyQt5 app not achieved.
    #   D-Bus communication does happen, as observed with:
    #
    #       busctl --user monitor org.freedesktop.portal.Documents org.freedesktop.portal.Desktop org.freedesktop.impl.portal.desktop.gtk
    #
    #   A LLM suggests it may have something to do with the process PID being
    #   that of the xdg-dbus-proxy, run by this user outside the sandbox. :shrug:
    set -- --block-fd 7 --sync-fd 7 \
        --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$dbus_proxy_path" \
        --perms 0555 --ro-bind-data 9 "$xdg_open" \
        --symlink "$xdg_open" "/usr/bin/chromium" \
        --symlink "$xdg_open" "/usr/bin/x-www-browser" \
        --ro-bind-data 6 "/.flatpak-info" \
        --bind "${XDG_RUNTIME_DIR:-/run/user/$uid}/doc" "${XDG_RUNTIME_DIR:-/run/user/$uid}/doc" \
        --setenv container 'sandbox-venv' \
        "$@"
else
    warn "Can't mock xdg-open or use XDG Desktop Portal: xdg-dbus-proxy not available."
    set -- --dir "/run/user/$uid" "$@"
fi

# Quiet very verbose, iterative args-constructing parts that follow
case $- in *x*) xtrace=-x ;; *) xtrace=+x ;; esac; set +x

# Collect binaries' lib dependencies
cache_file="$venv/sandbox/sandbox-venv.cache"
if [ -f "$cache_file" ]; then
    collect="$(cat "$cache_file")"
else
    warn 'Caching dependencies ... (Simply rerun pip to clear the cache.)'

    for exe in readelf ldd; do command_exists "$exe" || { warn "Missing executable: $exe"; exit 1; }; done
    lib_deps () {
        readelf -l "$1" >/dev/null 2>&1 || return 0  # Not a binary file
        readelf -l "$1" | awk '/interpreter/ {print $NF}' | tr -d '[]'
        ldd "$1" | awk '/=>/ { print $3 }' | grep -F -v "$venv" | grep -E '^/' || true
    }
    collect="$executables"
    for exe in $executables; do
        collect="$collect
            $(lib_deps "$exe")"
    done
    root_so_lib_dirs="
        /usr/lib/python3*/lib-dynload
        /usr/lib64/python3*/lib-dynload"
    # XXX: If some `git` tools are failing, add $(find /usr/lib/git-core -type f)
    for exe in $(find "$venv/lib" $root_so_lib_dirs -name '*.so' 2>/dev/null || true); do
        collect="$collect
            $(lib_deps "$exe")"
    done

    # Filter collect, warn on non-existant paths, unique sort, cull.
    # Use separate for-loop to expand globstar.
    prev="sandbox@"
    collect="
        $collect
        $ro_bind_extra
        $seccomp_libs
        $git_libs
        $py_libs"

    collect="$(
        for path in $collect; do
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
        done |
        # If user had already --bind /usr, avoid our /usr/lib
        while IFS= read -r path; do
            IFS='
            '; for prefix in $paths_from_args; do
                case "$path" in "${prefix%/}"/*) continue 2;; esac
            done
            echo "$path"
        done)"

    mkdir -p "${cache_file%/*}"
    echo "$collect" > "$cache_file"
fi
for path in $collect; do set -- --ro-bind "$path" "$path" "$@"; done

# RW bind $HOME and cache dirs for downloads etc.
home="${HOME:-"/home/$USER"}"
pip_cache="$home/${XDG_CACHE_HOME:-.cache}/pip"
mkdir -p "$venv/home" "$venv/cache" "$pip_cache"
[ ! "${SANDBOX_USE_PIP_CACHE-}" ] || {
    mkdir -p "$venv/cache/pip" &&
        echo "This dir is an artefact of Bubblewrap bind mounting. Real pip cache is in \$HOME/.cache/pip" \
        > "$venv/cache/pip/note.txt"
    set -- --bind "$pip_cache" "$home/.cache/pip" "$@"
}
set -- --bind "$venv/cache" "$home/.cache" "$@"
# RW-bind project dir (dir that contains .venv)
# but RO-bind some dirs like .venv and git
ro_bind_pwd_extra="
    ${venv##*/}
    .git"
for path in $ro_bind_pwd_extra; do
    [ ! -e "$proj_dir/$path" ] || set -- --ro-bind "$proj_dir/$path" "$proj_dir/$path" "$@"
done
# Lastly ... (this arg will appear first)
set -- --bind "$venv/home" "$home" --bind "$proj_dir" "$proj_dir" "$@"

# Pass our own redacted copy of env
# Expose all vars passed exclusively to this process (i.e. not its parent)
IFS=$(printf '\037')
for var in $(env -0 |
        grep -Ez -e '^('\
'USER|LOGNAME|UID|PATH|TERM|HOSTNAME|'\
'LANGUAGE|LANG|LC_.*?|TZ|'\
'https?_proxy|HTTPS?_PROXY|'\
'CC|CFLAGS|CXXFLAGS|CPPFLAGS|LDFLAGS|LDLIBS|MAKEFLAGS)=' \
                 -e "^($(env -0 |
                         cut -z -d= -f1 |
                         grep -Ezv "^($(cut -z -d= -f1 </proc/$PPID/environ |
                                        paste -z -s -d '|'))$" |
                         paste -z -s -d '|'))=" |
        grep -Ezv -e '^(_|LS_COLORS|PS1)=' |
        tr '\0' '\037'); do
    set -- --setenv "${var%%=*}" "${var#*=}" "$@"
done
unset IFS

set $xtrace

cwd="$(pwd)"

warn "exec bwrap [...] $formatted_cmdline"

[ ! "${VERBOSE:-${verbose:-}}" ] || set -x

# shellcheck disable=SC2086
bwrap \
    --dir /tmp \
    --dir "$cwd" \
    --bind "$tmpdir" "$tmpdir" \
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
    --setenv TMPDIR "$tmpdir" \
    --bind-data 5 /etc/passwd \
    --bind-data 4 /etc/group \
    "$@" \
    5<<EOF 4<<EOF2
$(getent passwd "$uid" nobody)
EOF
$(getent group "$(id -g)" nogroup adm sudo audio dip video plugdev staff users netdev scanner bluetooth lpadmin bumblebee)
EOF2

exec 7<&- && wait ${!-}  # Close FD 7, permitting xdg-dbus-proxy to exit
