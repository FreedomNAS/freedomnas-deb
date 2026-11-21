# freedomnas-deb

An APT repository for FreedomNAS on Debian: the five FreedomNAS packages
themselves, and the one third-party package Debian does not carry.

| Package | Source |
|---------|--------|
| `freedomnas-core`, `freedomnas-profiles`, `freedomnas-docs`, `freedomnas-webui`, `freedomnas-installer` | built from the checkouts beside this one |
| `topgrade` | built from upstream's source, without the self-update feature |
| `linux-image-freedomnas`, `linux-headers-freedomnas`, `zfsutils-freedomnas` | built from the `linux-freedomnas` checkout beside this one |
| `freedomnas-repository` | this repository's APT source and signing key, one build per component |

Everything else FreedomNAS installs on Debian is already in the
distribution — ZFS included, through `contrib` and `stable-backports`, which
the installer's `sources.list` enables — or comes from Docker's own
repository. topgrade is the only real gap.

Debian has no topgrade at all. `bin/build-topgrade-deb.sh` builds it from
upstream's source with cargo (the workflow installs Rust with rustup:
topgrade needs 1.88, trixie has 1.85). Upstream's release binary is built
with the self-update feature: before an update it tries to replace itself
and waits for an answer the WebUI cannot give. Built without that feature,
topgrade is updated only by APT. Arch and Gentoo build it the same way
(`topgrade` in freedomnas-arch, `app-admin/topgrade` in freedomnas-overlay).

## Building

```sh
bin/build-freedomnas-debs.sh         # all five FreedomNAS packages
bin/build-freedomnas-debs.sh freedomnas-webui
SNAPSHOT=1 bin/build-freedomnas-debs.sh   # ...as 0.9.9+<date and time>.<commit>
bin/version.sh --snapshot ../freedomnas-core
bin/build-topgrade-deb.sh            # the recorded topgrade version
bin/build-topgrade-deb.sh 17.16.0    # a specific one
bin/build-kernel-debs.sh             # kernel, headers, ZFS userspace (~1 hour)
COMPONENT=dev bin/build-repository-deb.sh   # APT source + key for `trixie dev`
bin/make-repo.sh                     # APT metadata for whatever is in pool/
GPG_KEY=<key-id> bin/make-repo.sh    # ...signed
```

`build-freedomnas-debs.sh` copies each source tree to a temporary directory
before building, because `dpkg-buildpackage` writes its artifacts next to
the tree it builds and a git checkout is not the place for them. It needs
`build-essential`, `dpkg-dev`, `debhelper`, `fakeroot`, `rsync` and — for `freedomnas-core` —
`dh-python`; `freedomnas-docs` is built with Debian's own `mkdocs`,
`mkdocs-material` and `python3-pymdownx`, and needs no network: its fonts are
in the repository.

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

## Publishing to GitHub

The repository is a flat APT repository in this repository's GitHub
releases, one per channel: `apt-main` for the releases, `apt-dev` for the
snapshots. `bin/publish-github.py` uploads the packages the release does not
hold yet, writes `Packages`, `Release` and `InRelease`, signs them with the
FreedomNAS archive key and deletes superseded versions:

```sh
GH_TOKEN=<token> COMPONENT=main bin/publish-github.py
GH_TOKEN=<token> COMPONENT=dev bin/publish-github.py     # snapshots, kept apart
```

`.github/workflows/publish-packages.yml` does this by itself: `dev` becomes a
snapshot in `apt-dev`, `main` a release in `apt-main`.
[docs/ci-setup.md](docs/ci-setup.md) lists the one secret it needs, the
private half of the signing key.

Then, on the machine, the one package `freedomnas-repository` sets up the
source and the key:

```sh
curl -LO https://github.com/FreedomNAS/freedomnas-deb/releases/download/apt-main/freedomnas-repository_1.2_all.deb
sudo apt install ./freedomnas-repository_1.2_all.deb
sudo apt update
sudo apt install freedomnas-installer
sudo freedomnas-install --mode inplace
```

`apt-dev` holds the same package for the snapshots. It writes
`/etc/apt/sources.list.d/freedomnas.sources` with the key in
`/usr/share/keyrings/freedomnas-archive-keyring.asc`, and removes the
one-line `freedomnas.list` the installer writes, since apt refuses one
repository listed twice with different `Signed-By` keys. It is published to
the repository it configures, so a new key or address reaches machines as an
ordinary update. The public key lives in `keys/freedomnas-archive-keyring.asc`;
`bin/build-repository-deb.sh` checks it against
`checksums/repository-key.sha256` and refuses a key that differs from it.
Replacing the key means updating both and raising the package version.

By hand, the same thing is:

```sh
curl -Lo /etc/apt/keyrings/freedomnas.asc \
    https://github.com/FreedomNAS/freedomnas-deb/releases/download/apt-main/freedomnas-archive-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/freedomnas.asc] \
    https://github.com/FreedomNAS/freedomnas-deb/releases/download/apt-main/ ./" \
    > /etc/apt/sources.list.d/freedomnas.list
apt update && apt install freedomnas-webui
```

A machine reads one channel only, `apt-main` or `apt-dev`; the kernel and
topgrade are in both.

`bin/make-repo.sh` and the `dists/` tree remain for serving the pool as
plain static files.

## Using it from a static copy

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
`packages/core.json` for Debian the way `app-admin/topgrade` already
has for Gentoo.

## License

GPL-2.0-or-later: the GNU General Public License, version 2 or (at your
option) any later version. The text of version 2 is in `LICENSE`.

The packages built from here keep the licenses of what they package —
MPL-2.0 for the FreedomNAS components.
