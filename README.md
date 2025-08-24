sandbox-venv: secure container virtualenv wrapper
=================================================

[![Build status](https://img.shields.io/github/actions/workflow/status/kernc/sandbox-venv/ci.yml?branch=master&style=for-the-badge)](https://github.com/kernc/sandbox-venv/actions)
[![Language: shell / Bash](https://img.shields.io/badge/lang-Shell-peachpuff?style=for-the-badge)](https://github.com/kernc/sandbox-venv)
[![Source lines of code](https://img.shields.io/endpoint?url=https%3A%2F%2Fghloc.vercel.app%2Fapi%2Fkernc%2Fsandbox-venv%2Fbadge?filter=.sh%26format=human&style=for-the-badge&label=SLOC&color=skyblue)](https://ghloc.vercel.app/kernc/sandbox-venv)
[![Script size](https://img.shields.io/github/size/kernc/sandbox-venv/build/sandbox-venv?style=for-the-badge&color=skyblue)](https://github.com/kernc/sandbox-venv)
[![Issues](https://img.shields.io/github/issues/kernc/sandbox-venv?style=for-the-badge)](https://github.com/kernc/sandbox-venv/issues)
[![Sponsors](https://img.shields.io/github/sponsors/kernc?color=pink&style=for-the-badge)](https://github.com/sponsors/kernc)


#### Problem statement

Python virtual environments (package
[`virtualenv`](https://virtualenv.pypa.io/en/latest/)
or built-in module
[venv](https://docs.python.org/3/library/venv.html))
isolate your project’s interpreter and dependencies, but they offer
**no security or execution sandboxing** like a virtual machine or a Docker
container would. Therefore, running virtualenv Python programs as-is (unsecured),
**any [rogue dependency](https://www.google.com/search?q=malicious+python+packages&tbm=nws)\*
🎯 or [hacked library code](https://www.google.com/search?q=(hacked+OR+hijacked+OR+backdoored+OR+"supply+chain+attack")+(npm+OR+pypi)&tbm=nws&num=100)
:pirate_flag: ([et cet.](https://slsa.dev/spec/draft/threats-overview) :warning:)
can wreak havoc, including access all your private parts** :bangbang:—think
current user's credentials and personal bits like:
* `~/.ssh/id_ed25519`,
* `~/.pki/nssdb/`,
* `~/.mozilla/firefox/<profile>/key4.db`,
* `~/.mozilla/firefox/<profile>/formhistory.sqlite` ...

<sub>✱ Installing something as seemingly harmless as the popular package _poetry_ pulls in
[nearly a hundred dependencies or over 70 MB](doc/deps-stats.txt)
of Python sources! 😬</sub>

In someone else's words:

>> Using virtualenv is more secure?
> 
> [No. Not in the slightest.](https://www.reddit.com/r/Python/comments/5sm6zm/using_virtualenv_is_more_secure/)

#### Solution

In order to execute installed Python programs in secure virtual environments,
one is better advised to either look to OS VM primitives like those provided by Docker
and [containers](https://github.com/containers/), e.g.:
```shell
podman run -it -v .:/src python:3 bash  # ...
```
The simpler alternative is **automatic lightweight container wrapping with
[bubblewrap](https://github.com/containers/bubblewrap)** (of
[Flatpak](https://en.wikipedia.org/wiki/Flatpak) fame)
using `sandbox-venv` script from this repo.


Installation
------------
There are **no dependencies other than a POSIX shell** with
[its standard set of utilities](https://en.wikipedia.org/wiki/List_of_POSIX_commands)
**and `bubblewrap`**.
The installation instructions, as well as the script runtime,
should work similarly on all relevant compute platforms,
including GNU/Linux and even
[Windos/WSL](https://learn.microsoft.com/en-us/windows/wsl/install). 🤞

```shell
# Install required dependencies, e.g.
sudo apt install binutils bubblewrap python3
 
# Download the script and put it somewhere on PATH
curl -vL 'https://bit.ly/sandbox-venv' | sudo tee /usr/local/bin/sandbox-venv
sudo chmod +x /usr/local/bin/sandbox-venv  # Mark executable

sandbox-venv --help
# Usage: sandbox-venv [VENV_DIR] [BWRAP_OPTS]
sandbox-venv path/to/my-project/.venv
```

Usage
-----
Whenever you create a new virtual environment,
simply invoke `sandbox-venv` on it afterwards, e.g.:
```shell
cd project
python -m venv .venv  # Create a new project virtualenv
sandbox-venv .venv    # Passing virtualenv dir is optional; defaults to ".venv"
```
From now on, directory _.venv_ and everything under it
(in particular, everything in the _bin_ folder,
e.g. `.venv/bin/python`, `.venv/bin/pip` etc.)
sets up and transparently runs in a secure container sandbox.


#### Extra Bubblewrap arguments

Other than the optional virtualenv dir, **all arguments initially passed to
`sandbox-venv` are forwarded to bubblewrap**. See `bubblewrap --help` or
[`man 1 bwrap`](https://manpages.debian.org/unstable/bwrap). You can also pass additional bubblewrap arguments to individual
process invocations via **`$BWRAP_ARGS` environment variable**. E.g.:

```sh
BWRAP_ARGS='--bind /lib /lib' \
    python -c 'import os; print(os.listdir("/lib"))'
```

To run the sandboxed process as **superuser**
(while still retaining all the security functionality of the container sandbox),
e.g. to open privileged ports, use args:

    --uid 0 --cap-add cap_net_bind_service


#### Filesystem mounts

The directory that contains your venv dir, i.e. `.venv/..` or
**the project directory, is mounted with read-write permissions**,
while everything else (including `project/.git`)
is mounted read-only. In addition:

* `"$venv/cache"` is bind-mounted as `"$HOME/.cache"`
* `"$HOME/.cache/pip"` is bind-mounted as `"$HOME/.cache/pip"`
  (only if environment variable `SANDBOX_USE_PIP_CACHE=` is set as this may
  enable cache poisoning attachs).

To mount extra endpoints, use Bubblewrap switches `--bind` or `--bind-ro`.
Anything else not explicitly mounted by an extra CLI switch
is lost upon container termination.


#### Runtime monitoring

If **environment variable `VERBOSE=`** is set to a non-empty value,
the full `bwrap` command line is emitted to stderr before execution.

You can list bubblewraped processes using the command `lsns`
or the following shell function:

```sh
list_bwrap () { lsns -u -W | { IFS= read header; echo "$header"; grep bwrap; }; }

list_bwrap  # Function call
```

You can run `$venv/bin/shell` to spawn **interactive shell inside the sandbox**.


Viable alternatives
-------------------
1. A popular alternative are the aforementioned Docker/OCI containers
   and manual management of their runtime. This comes free when the
   worked on project itself deals in
   [Continerfiles](https://manpages.debian.org/unstable/Containerfile). 
2. On Linux, [AppArmor](https://apparmor.net), even with
   [apparmor.d](https://github.com/roddhjav/apparmor.d)
   applied, doesn't ship a generic `python` profile, so one would go
   through direct `aa-exec --profile my-custom-env`, but writing
   custom AppArmor profiles is less common than simply using containers.
3. [Firejail](https://github.com/netblue30/firejail/).
   An indie C project with virtually no dependencies (which
   [<del>Red Hat</del><ins>IBM</ins> has a reasonable position on](https://github.com/containers/bubblewrap?tab=readme-ov-file#related-project-comparison-firejail))
   that sets up its own sandbox. I guess it's a matter of trust.
   Similarly to AppArmor, requires writing a custom profile.
4. On macOS, [`sandbox-exec`](https://igorstechnoclub.com/sandbox-exec/)
   or Apple Containerization®.

In comparison to the above, `sandbox-venv` is like `chroot` on steroids.
It uses the same isolation primitives that containers use
(process sandbox via Linux namespaces, isolated filesystem view),
but without all of the container runtime baggage—YMMV.
