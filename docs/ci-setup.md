# CI setup

`.forgejo/workflows/publish-packages.yml` rebuilds the packages and pushes
them to Codeberg's Debian registry. It needs two secrets here, and one in
each component repository. Until they are set, the workflow fails at the
step that would have used them — nothing is published by accident.

## 1. The registry token (secrets on **this** repository)

The workflow uploads with `bin/publish-codeberg.sh`, which authenticates as
a user.

1. On Codeberg: Settings → Applications → Access Tokens.
2. Create a token with the **`package`** scope, write access. That is all it
   needs: it cannot push code or change settings.
3. Copy it — Codeberg shows it once.
4. Here: Settings → Actions → Secrets, add
   - `PACKAGE_REGISTRY_USER` — the Codeberg username the token belongs to
   - `PACKAGE_REGISTRY_TOKEN` — the token

**Rotating**: create the new token, update `PACKAGE_REGISTRY_TOKEN`, then
revoke the old one. Nothing overlaps, because each run reads the secret when
it starts.

## 2. The trigger token (secret on **each component** repository)

`freedomnas-core`, `-profiles`, `-webui` and `-installer` each carry
`.forgejo/workflows/notify-deb-repo.yml`, which asks this repository's
workflow to run. That API call needs a token with permission to trigger
workflows on `FreedomNAS/freedomnas-deb`.

1. Create a token with **`write:repository`** scope.
2. Add it to all four repositories as `DEB_REPO_TRIGGER_TOKEN`.

This mirrors `IMAGE_BUILDER_TRIGGER_TOKEN`, which those repositories already
use to ask freedomnas-image-builder to rebuild its images; the two are
independent, and one token may be reused for both only if you are happy for
a single revocation to stop both.

## 3. Which build a push produces

| Push to | Version | Published to |
|---------|---------|--------------|
| `dev` | `1.0+<date>.<commit>-1`, from `bin/version.sh --snapshot` | component `dev` |
| `main` | what `debian/changelog` says, e.g. `1.0-1` | component `main` |

Installed systems follow `main`, which is what
`installer-debian.json`'s `repositories.core` writes into
`sources.list.d`. To follow snapshots on a test machine, add a second line
with `dev` in place of `main`.

A base version is raised by editing `debian/changelog` in the component
repository — `1.0` to `1.1` when a change deserves it. Small changes need
nothing: the snapshot suffix keeps every build distinct, and
`dpkg --compare-versions` puts them in the right order:

```
1.0-1  <  1.0+20260923.a54c544-1  <  1.1-1
```

## 4. Runner

No privileged access is needed — a Debian container, `dpkg-buildpackage` and
`curl` — so Codeberg's hosted runner can do it. The job installs `nodejs`
in the container first: `actions/checkout` is a Node action and
`debian:trixie` ships without it. Codeberg's hosted Forgejo
Actions is in open alpha, so if it is unavailable the same workflow runs on a
self-hosted runner unchanged; only `runs-on` has to name it.

Without any runner at all, the scripts are still the whole of the job:

```sh
SNAPSHOT=1 bin/build-freedomnas-debs.sh
CODEBERG_USER=<user> CODEBERG_TOKEN=<token> COMPONENT=dev bin/publish-codeberg.sh
```
