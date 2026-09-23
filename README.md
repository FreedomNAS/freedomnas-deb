# freedomnas-deb

An APT repository for FreedomNAS on Debian: the four FreedomNAS packages
themselves, and the one third-party package Debian does not carry.

| Package | Source |
|---------|--------|
| `freedomnas-core`, `freedomnas-profiles`, `freedomnas-webui`, `freedomnas-installer` | built from the checkouts beside this one |
| `topgrade` | upstream's release binary, wrapped in a `.deb` |

Everything else FreedomNAS installs on Debian is already in the
distribution — ZFS included, through `contrib` and `stable-backports`, which
the installer's `sources.list` enables — or comes from Docker's own
repository. topgrade is the only real gap.

Debian has no topgrade at all, and building it from source pulls the Rust
toolchain and several hundred crates — on a NAS, a long compile for a
program that upstream already ships as a statically linked musl binary.
`bin/build-topgrade-deb.sh` wraps that binary in a `.deb`; nothing is
compiled here. Gentoo gets the same treatment through
`app-admin/topgrade-bin` in freedomnas-overlay.

## Building

```sh
bin/build-freedomnas-debs.sh         # all four FreedomNAS packages
bin/build-freedomnas-debs.sh freedomnas-webui
bin/build-topgrade-deb.sh            # the recorded topgrade version
bin/build-topgrade-deb.sh 17.12.1    # a specific one
bin/make-repo.sh                     # APT metadata for whatever is in pool/
GPG_KEY=<key-id> bin/make-repo.sh    # ...signed
```

`build-freedomnas-debs.sh` copies each source tree to a temporary directory
before building, because `dpkg-buildpackage` writes its artifacts next to
the tree it builds and a git checkout is not the place for them. It needs
`dpkg-dev`, `debhelper`, `fakeroot`, `rsync` and — for `freedomnas-core` —
`python3-all`, `python3-setuptools` and `pybuild-plugin-pyproject`.

The first build of a version records the tarball's SHA-256 under
`checksums/`; every build after that verifies against it, so an upstream
release cannot change underneath us. Commit that file — it is the only
build artifact that belongs in git.

`make-repo.sh` needs `apt-ftparchive` (Debian's `apt-utils`). On a host
without it, run it inside a Debian container: the pool is plain files and
nothing in the script is host-specific.

## Layout

```
pool/main/t/topgrade/topgrade_<version>_amd64.deb
dists/stable/Release            (+ Release.gpg and InRelease when signed)
dists/stable/main/binary-amd64/Packages{,.gz}
checksums/topgrade-<version>.sha256
```

Only `bin/`, `checksums/` and this file are tracked. The pool and the
`dists` tree are rebuilt from them, so they stay out of git.

## Using it

Serve the directory over HTTP — any static host will do — and on the
FreedomNAS machine:

```sh
echo "deb [signed-by=/usr/share/keyrings/freedomnas.gpg] https://<host>/ stable main" \
    > /etc/apt/sources.list.d/freedomnas.list
```

with the public half of the signing key in
`/usr/share/keyrings/freedomnas.gpg`. An unsigned repository needs
`[trusted=yes]` instead, which is fine for a local test and wrong for
anything else.

Then `apt install freedomnas-webui` pulls `freedomnas-core` and
`freedomnas-profiles` with it, and `freedomnas-installer` is there for a
machine that will install other editions.

A local test needs no web server at all:

```sh
echo "deb [trusted=yes] file://$PWD stable main" \
    | sudo tee /etc/apt/sources.list.d/freedomnas-local.list
sudo apt update && apt-cache policy freedomnas-webui
```

Once the repository is hosted, the Debian edition's installer profile gets
a `repositories.core` entry that writes that file, and `topgrade` joins
`packages/core.json` for Debian the way `app-admin/topgrade-bin` already
has for Gentoo.
