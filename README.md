# freedomnas-deb

An APT repository for FreedomNAS on Debian: the five FreedomNAS packages
themselves, and the one third-party package Debian does not carry.

| Package | Source |
|---------|--------|
| `freedomnas-core`, `freedomnas-profiles`, `freedomnas-docs`, `freedomnas-webui`, `freedomnas-installer` | built from the checkouts beside this one |
| `topgrade` | upstream's release binary, wrapped in a `.deb` |
| `linux-image-freedomnas`, `linux-headers-freedomnas`, `zfsutils-freedomnas` | built from the `linux-freedomnas` checkout beside this one |

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
bin/build-freedomnas-debs.sh         # all five FreedomNAS packages
bin/build-freedomnas-debs.sh freedomnas-webui
SNAPSHOT=1 bin/build-freedomnas-debs.sh   # ...as 0.9.9+<date and time>.<commit>
bin/version.sh --snapshot ../freedomnas-core
bin/build-topgrade-deb.sh            # the recorded topgrade version
bin/build-topgrade-deb.sh 17.12.3    # a specific one
bin/build-kernel-debs.sh             # kernel, headers, ZFS userspace (~1 hour)
DRY_RUN=1 bin/prune-registry.py      # what the workflow would delete: all but the
                                     # 2 newest snapshots, releases and kernels
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

## Publishing to Codeberg

Codeberg runs Forgejo, which has a Debian registry: it builds and signs the
repository metadata itself, so nothing here has to be served or signed by
hand, and the `.deb` files land in the packages quota rather than in git.

```sh
CODEBERG_USER=<username> CODEBERG_TOKEN=<token> bin/publish-codeberg.sh
COMPONENT=dev ... bin/publish-codeberg.sh     # snapshots, kept apart
```

`.forgejo/workflows/publish-packages.yml` does this by itself on every push
to the component repositories: `dev` becomes a snapshot in the `dev`
component, `main` a release in `main`. [docs/ci-setup.md](docs/ci-setup.md)
lists the two secrets it needs.

The token needs the `package` scope with write access (Settings →
Applications → Access Tokens). It is read from the environment and handed to
curl on stdin, so it stays out of the process list. A version that is
already published is refused: delete it in the web interface, or raise the
version in `debian/changelog`.

Then, on the machine:

```sh
curl -o /etc/apt/keyrings/freedomnas.asc \
    https://codeberg.org/api/packages/FreedomNAS/debian/repository.key
echo "deb [signed-by=/etc/apt/keyrings/freedomnas.asc] \
    https://codeberg.org/api/packages/FreedomNAS/debian trixie main" \
    > /etc/apt/sources.list.d/freedomnas.list
apt update && apt install freedomnas-webui
```

`main` holds the releases, `dev` the snapshots; the kernel and topgrade are
in both. A machine reads one component only, `main` or `dev`: the
installer's Debian profile writes the one matching the branch its image or
live ISO was built from.

`bin/make-repo.sh` and the `dists/` tree remain for serving the pool as
plain static files, which is the fallback if the registry is ever not an
option.

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
`packages/core.json` for Debian the way `app-admin/topgrade-bin` already
has for Gentoo.

## License

GPL-2.0-or-later: the GNU General Public License, version 2 or (at your
option) any later version. The text of version 2 is in `LICENSE`.

The packages built from here keep the licenses of what they package —
MPL-2.0 for the FreedomNAS components.
