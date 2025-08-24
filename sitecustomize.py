#!/usr/bin/python3
"""
Importing this module inits seccomp/pyseccomp, restricting allowed syscalls to those
listed in SANDBOX_SECCOMP_ALLOW environment variable (or, by default, the list below).
The module is imported automatically upon startup when on PYTHONPATH.

https://docs.python.org/3/library/site.html#module-sitecustomize
"""
import os
import re
import sys

# XXX: You can debug this list (e.g. update missing items) by
#  looking for EPERM in `strace -f` output.
ALLOW_SYSCALLS = [
    # Process & signals
    "clone", "clone3", "fork", "vfork", "execve", "exit", "exit_group",
    "kill", "tgkill", "tkill", "wait4", "getpid", "getppid", "gettid",
    "prctl", "arch_prctl", "getpgrp",
    "pidfd_open", "pidfd_send_signal",
    "sigaction", "sigreturn",
    "rt_sigaction", "rt_sigreturn",
    "rt_sigprocmask", "rt_sigpending", "rt_sigsuspend",
    "sigaltstack", "rseq", "process_madvise",

    # File I/O
    "open", "openat", "close", "close_range", "read", "write",
    "name_to_handle_at",
    "pread64", "pwrite64", "preadv", "pwritev", "preadv2", "pwritev2",
    "lseek",
    "stat", "statx", "fstat", "lstat", "fstatat64", "newfstatat",
    "stat64", "lstat64", "fstat64", "fadvise64",
    "faccessat2", "getdents", "getdents64", "access",
    "unlink", "unlinkat", "mkdir", "mkdirat", "rmdir",
    "rename", "renameat", "renameat2",
    "readlink", "readlinkat", "symlink", "symlinkat", "link", "linkat",
    "truncate", "ftruncate", "utime", "utimes", "futimesat", "utimensat",
    "chown", "fchown", "lchown", "fchmod", "fchmodat", "chmod", "mknod", "mknodat",
    "getxattr", "setxattr", "listxattr", "removexattr",

    # fd ops
    "dup", "dup2", "dup3", "pipe", "pipe2",
    "fcntl", "flock", "fsync", "fdatasync",
    "readahead",
    "splice", "tee", "vmsplice",

    # mmap / mem / threads
    "brk", "mmap", "mmap2", "munmap", "mremap", "mprotect", "madvise", "mincore",
    "futex", "futex_time64", "futex_waitv", "set_tid_address", "set_robust_list", "get_robust_list",
    "sched_yield", "sched_getaffinity",
    "mlock", "munlock", "mlockall", "munlockall",
    "get_mempolicy", "set_mempolicy", "mbind", "migrate_pages", "move_pages",
    "membarrier",

    # Time / clocks
    "nanosleep", "clock_gettime", "clock_getres", "gettimeofday", "time",
    "clock_nanosleep", "clock_gettime64",
    "timer_create", "timer_settime", "timer_gettime", "timer_delete",
    "setitimer", "getitimer", "times",
    "timerfd_create", "timerfd_settime", "timerfd_gettime",

    # Networking
    "socket", "socketpair", "socketcall", "bind", "listen",
    "accept", "accept4", "connect",
    "getsockname", "getpeername",
    "sendto", "recvfrom", "sendmsg", "recvmsg", "shutdown",
    "setsockopt", "getsockopt",
    "recvmmsg", "sendmmsg",
    "sendfile", "sendfile64",

    # epoll/poll/select
    "epoll_create", "epoll_create1", "epoll_ctl", "epoll_wait",
    "epoll_pwait", "epoll_pwait2",
    "poll", "ppoll", "ppoll_time64", "select", "pselect6",
    "eventfd", "eventfd2",

    # Descriptors / metadata
    "ioctl", "readv", "writev",
    "getcwd", "chdir", "fchdir",
    "statfs", "fstatfs", "statfs64", "fstatfs64",

    # UIDs/GIDs (read + drop privileges)
    "getuid", "geteuid", "getgid", "getegid", "getgroups",
    "getresuid", "getresgid", "setresuid", "setresgid", "setreuid", "setregid",
    "setuid", "setgid",

    # Limits / info
    "getrlimit", "setrlimit", "prlimit64", "uname", "sysinfo", "getrusage", "umask",

    # Random
    "getrandom",

    # Misc
    "seccomp", "capget",
    "shmget", "shmat", "shmdt", "shmctl",
]


try:
    allow_syscalls = re.findall(r'\w+', os.environ['SANDBOX_SECCOMP_ALLOW'])
except KeyError:
    allow_syscalls = ALLOW_SYSCALLS

if allow_syscalls:
    try:
        import seccomp
    except ImportError:
        try:
            import pyseccomp as seccomp
        except ImportError:
            seccomp = None
            if sys.platform.startswith('linux'):
                print("sandbox-venv/seccomp: Python package 'seccomp' (or 'pyseccomp') "
                      "not available. If you want seccomp support, apt install python3-seccomp "
                      "(requires venv created with --system-site-packages) "
                      "or pip install pyseccomp.", file=sys.stderr)
    if seccomp:
        print(f'sandbox-venv/seccomp: allowing {len(allow_syscalls)} syscalls', file=sys.stderr)
        default_action = seccomp.ERRNO(seccomp.errno.EPERM)  # EPERM, Operation not permitted
        filter = seccomp.SyscallFilter(default_action)
        for syscall in allow_syscalls:
            # print(syscall, file=sys.stderr)
            filter.add_rule(seccomp.ALLOW, syscall)
        filter.load()
