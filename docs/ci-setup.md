# CI setup

`.forgejo/workflows/publish-packages.yml` rebuilds the packages and pushes
them to Codeberg's Debian registry. It needs two organization secrets, and
one in each component repository. Until they are set, the workflow fails at the
step that would have used them — nothing is published by accident.

## 1. The registry token (secrets on the **FreedomNAS organization**)

The workflow uploads with `bin/publish-codeberg.sh` and deletes superseded
versions with `bin/prune-registry.py`; both authenticate as a user.
freedomnas-arch's workflow uses the same two secrets.

1. On Codeberg: Settings → Applications → Access Tokens.
2. Create a token with the **`package`** scope, write access. That is all it
   needs: it cannot push code or change settings.
3. Copy it — Codeberg shows it once.
4. On the organization: FreedomNAS → Settings → Actions → Secrets, add
   - `PACKAGE_REGISTRY_USER` — the Codeberg username the token belongs to
   - `PACKAGE_REGISTRY_TOKEN` — the token

Secrets with the same name on a repository override the organization's, so
keep none there.

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

Codeberg's own runners do not pick these jobs up: the workflow asks for
`runs-on: docker`, and that label is served by a self-hosted Forgejo runner
registered on the **FreedomNAS organisation**, so one runner serves every
repository in it. The job needs no privileged access — a Debian container,
`dpkg-buildpackage` and `curl` — so any machine with Docker will do.

Setting one up:

1. Install `forgejo-runner` (12 or later) and Docker, and give the runner's
   user access to the Docker socket.
2. On Codeberg: FreedomNAS → Settings → Actions → Runners → **Create new
   runner**. Codeberg shows a `url`, a `uuid` and a `token`.
3. Put them in the runner's `config.yaml`, with the token in a file only the
   runner's user can read:

   ```yaml
   runner:
     labels:
       - "docker:docker://node:20-bookworm"
   server:
     connections:
       codeberg:
         url: https://codeberg.org/
         uuid: <uuid>
         token_url: file:/var/lib/forgejo-runner/codeberg-token
   container:
     valid_volumes:
       - /var/cache/freedomnas-ccache/**
   ```

   `valid_volumes` lets the jobs mount the kernel's ccache, a host
   directory kept between runs (`debian/` and `arch/` under it, one per
   workflow, since their compilers differ). With it a kernel rebuild
   recompiles only what changed; without it the workflow fails to start.
   Each cache is capped at 10 GB (`CCACHE_MAXSIZE`).

4. Start `forgejo-runner daemon --config <path>/config.yaml` as a service.
   The log says `declared successfully` once Codeberg accepts it, and the
   runner shows as idle on the organisation's runner page.

Codeberg lets a runner ask for work every 30 seconds at most, so a job can
wait that long before it starts.

The job runs in `debian:trixie` and installs its own tooling first:
`build-essential`, which `dpkg-checkbuilddeps` always requires but
`--no-install-recommends` leaves out, and `nodejs`, because
`actions/checkout` is a Node action and the image ships without it.

A runner whose user is in the `docker` group is root on its machine, and
anyone who can push a workflow to the organisation can use it. That is fine
while the organisation's members are trusted; otherwise run it in a VM.

Without any runner at all, the scripts are still the whole of the job:

```sh
SNAPSHOT=1 bin/build-freedomnas-debs.sh
CODEBERG_USER=<user> CODEBERG_TOKEN=<token> COMPONENT=dev bin/publish-codeberg.sh
```
