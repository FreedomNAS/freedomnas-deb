# freedomnas-debian-repo

An APT repository for the packages Debian does not carry but FreedomNAS
needs. Today that is one package: **topgrade**, which the WebUI's Updates
page runs.

Debian has no topgrade at all, and building it from source pulls the Rust
toolchain and several hundred crates — on a NAS, a long compile for a
program that upstream already ships as a statically linked musl binary.
`bin/build-topgrade-deb.sh` wraps that binary in a `.deb`; nothing is
compiled here. Gentoo gets the same treatment through
`app-admin/topgrade-bin` in freedomnas-overlay.

## Building

```sh
bin/build-topgrade-deb.sh            # latest recorded version
bin/build-topgrade-deb.sh 17.12.1    # a specific one
bin/make-repo.sh                     # APT metadata for whatever is in pool/
GPG_KEY=<key-id> bin/make-repo.sh    # ...signed
```

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

Once the repository is hosted, the Debian edition's installer profile gets
a `repositories.core` entry that writes that file, and `topgrade` joins
`packages/core.json` for Debian the way `app-admin/topgrade-bin` already
has for Gentoo.
