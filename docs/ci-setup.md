# CI setup

`.github/workflows/publish-packages.yml` rebuilds the packages and publishes
them as a flat, signed APT repository in this repository's GitHub releases:
`apt-dev` for the development snapshots, `apt-main` for the releases. Every
package and the metadata (`Packages`, `Release`, `InRelease`, the signing
key) are assets of that release (ADR-003 in freedomnas-specs).

The Forgejo workflow under `.forgejo/workflows/` is switched off: it runs
only when dispatched by hand, so that nothing is published twice.

## 1. The signing key (secret on the **FreedomNAS organization**)

The repository is signed with the FreedomNAS archive key. Its public half is
`keys/freedomnas-archive-keyring.asc` (recorded in
`checksums/repository-key.sha256` and shipped by `freedomnas-repository`);
the private half is the secret **`APT_SIGNING_KEY`**, the armored output of
`gpg --armor --export-secret-keys <fingerprint>`:

```sh
gh secret set APT_SIGNING_KEY --org FreedomNAS --visibility all < APT_SIGNING_KEY.asc
```

Until it is set, the `publish` job stops before uploading anything.

The workflow itself needs no other secret: it publishes with the
`GITHUB_TOKEN` GitHub gives every run (`permissions: contents: write`).

## 2. Triggers

- **Manual**: Actions → publish-packages → Run workflow, `ref` = `dev` or
  `main`.
- **Daily** at 04:17 UTC, a `dev` snapshot.
- **From the component repositories**: a `repository_dispatch` of type
  `component-pushed` with `{"ref": "dev"}` or `{"ref": "main"}` in its
  payload.

## 3. Which build a push produces

| Ref | Version | Published to |
|-----|---------|--------------|
| `dev` | `0.9.9+<UTC date and time>.<commit>-1`, from `bin/version.sh --snapshot` | release `apt-dev` |
| `main` | what `debian/changelog` says at the newest `vX.Y.Z` tag, e.g. `0.9.9-1` | release `apt-main` |

A system follows one channel only: `freedomnas-repository` for `dev` points
at `apt-dev`, for `main` at `apt-main`. Never list both: the snapshots sort
above the releases.

```
0.9.9-1  <  0.9.9+20261004103357.8232059-1  <  0.9.9+20261004123558.3f8bb72-1  <  1.0-1
```

## 4. Jobs

| Job | Runs on | Does |
|-----|---------|------|
| `packages` | `ubuntu-24.04`, in `debian:trixie` | the FreedomNAS packages, topgrade, freedomnas-repository and the community modules |
| `kernel-check` | `ubuntu-24.04` | whether this kernel version is already in the release (`CHECK_ONLY=1 bin/build-kernel-debs.sh`) |
| `kernel` | `ubuntu-24.04`, in `debian:trixie` | only when the kernel is missing; the ccache is kept with `actions/cache` |
| `publish` | `ubuntu-24.04`, in `debian:trixie` | `bin/publish-github.py` with everything the others built |

The build jobs only build and hand their pool over as artifacts; `publish`
runs once at the end, so two jobs never write the same release, and the
workflow's `concurrency` group keeps two runs of the same channel apart.

A cold kernel build takes about 95 minutes on the 4-vCPU runners, well
inside their six hour limit.

`bin/publish-github.py` uploads only the packages the release does not hold
yet, rewrites the metadata, and deletes what is superseded: every package
keeps its `KEEP` (2) newest snapshots and releases, and the 2 newest kernels
stay with their headers. GitHub renames assets whose name holds characters
other than letters, digits and `._+-` (a `~` becomes `.`), so the script
uploads every package under that safe name and writes it in `Packages`.

Without GitHub Actions, the scripts are still the whole of the job:

```sh
SNAPSHOT=1 bin/build-freedomnas-debs.sh
GH_TOKEN=<token> COMPONENT=dev bin/publish-github.py
```
