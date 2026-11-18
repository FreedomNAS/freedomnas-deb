#!/usr/bin/env python3
"""Publish the pool as a flat, signed APT repository in a GitHub Release.

    COMPONENT=dev bin/publish-github.py
    COMPONENT=main GPG_KEY=<fingerprint> bin/publish-github.py pool/main/t/topgrade/*.deb
    DRY_RUN=1 COMPONENT=dev bin/publish-github.py

The repository of a component is the release `apt-<component>` of
GITHUB_APT_REPO (FreedomNAS/freedomnas-deb): every package and the metadata
are assets of that release, and an installation reads it with

    deb [signed-by=...] https://github.com/<repo>/releases/download/apt-<component>/ ./

Every package keeps its KEEP newest snapshots and its KEEP newest releases;
the KEEP newest kernels stay, older ones go with their headers.
"""
import functools
import gzip
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

REPO = os.environ.get("GITHUB_APT_REPO", "FreedomNAS/freedomnas-deb")
COMPONENT = os.environ.get("COMPONENT", "main")
TAG = f"apt-{COMPONENT}"
KEEP = int(os.environ.get("KEEP", "2"))
GPG_KEY = os.environ.get("GPG_KEY", "")
DRY_RUN = bool(os.environ.get("DRY_RUN"))
REPO_DIR = Path(__file__).resolve().parent.parent
KEYRING = REPO_DIR / "keys" / "freedomnas-archive-keyring.asc"
BASE = f"https://github.com/{REPO}/releases/download/{TAG}/"

UNSAFE = re.compile(r"[^A-Za-z0-9._+-]")
KERNEL = re.compile(r"^linux-(?:image|headers)-(\d.*)$")
SNAPSHOT = re.compile(r"\+\d{8}")
METADATA = ("Packages", "Packages.gz", "Release", "Release.gpg", "InRelease", KEYRING.name)


def run(*args, capture=False, check=True, cwd=None):
    result = subprocess.run(args, check=check, cwd=cwd, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else result


def gh(*args, capture=False, check=True):
    return run("gh", *args, "-R", REPO, capture=capture, check=check)


def asset_name(path):
    return UNSAFE.sub(".", Path(path).name)


def ensure_release():
    if gh("release", "view", TAG, capture=True, check=False):
        return
    print(f"==> creating release {TAG}")
    if not DRY_RUN:
        gh("release", "create", TAG, "--title", f"APT repository ({COMPONENT})",
           "--notes", f"Flat APT repository of the `{COMPONENT}` channel: {BASE}",
           "--latest=false", *(["--prerelease"] if COMPONENT != "main" else []))


def assets():
    out = gh("release", "view", TAG, "--json", "assets", "--jq", ".assets[].name",
             capture=True, check=False) or ""
    return set(out.split())


def paragraphs(text):
    for block in re.split(r"\n\s*\n", text.strip()):
        if block.strip():
            yield block.strip()


def field(paragraph, name):
    match = re.search(rf"^{name}: (.*)$", paragraph, re.M)
    return match.group(1).strip() if match else ""


def compare_versions(a, b):
    if a == b:
        return 0
    return -1 if run("dpkg", "--compare-versions", a, "lt", b, check=False).returncode == 0 else 1


def doomed(entries):
    groups = defaultdict(list)
    kernels = defaultdict(list)
    for entry in entries:
        package, version = field(entry, "Package"), field(entry, "Version")
        kernel = KERNEL.match(package)
        if kernel:
            kernels[kernel.group(1)].append(entry)
        else:
            groups[(package, bool(SNAPSHOT.search(version)))].append(entry)

    newest_first = functools.cmp_to_key(lambda a, b: compare_versions(field(b, "Version"), field(a, "Version")))
    for versions in groups.values():
        yield from sorted(versions, key=newest_first)[KEEP:]

    by_release = sorted(kernels, key=functools.cmp_to_key(lambda a, b: compare_versions(b, a)))
    for release in by_release[KEEP:]:
        yield from kernels[release]


def scan(directory):
    out = run("dpkg-scanpackages", "--multiversion", ".", "/dev/null", capture=True, cwd=directory)
    return [re.sub(r"^Filename: .*?([^/]+)$", r"Filename: ./\1", p, flags=re.M) for p in paragraphs(out)]


def main():
    for tool in ("gh", "dpkg-scanpackages", "apt-ftparchive", "gpg"):
        if not shutil.which(tool):
            sys.exit(f"publish-github.py: {tool} not found")
    if COMPONENT not in ("main", "dev"):
        sys.exit(f"publish-github.py: COMPONENT must be main or dev, not {COMPONENT}")

    debs = [Path(a) for a in sys.argv[1:]] or sorted((REPO_DIR / "pool").rglob("*.deb"))
    ensure_release()
    published = assets()

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        entries = []
        if "Packages" in published:
            gh("release", "download", TAG, "-p", "Packages", "-D", str(tmp / "old"))
            entries = list(paragraphs((tmp / "old" / "Packages").read_text()))

        new = tmp / "new"
        new.mkdir()
        for deb in debs:
            name = asset_name(deb)
            if name in published:
                print(f"==> {name}: already published")
                continue
            shutil.copy2(deb, new / name)
            print(f"==> {name}: new")
        staged = sorted(new.iterdir())
        if staged:
            entries += scan(new)

        drop = list(doomed(entries))
        drop_names = {field(e, "Filename")[2:] for e in drop}
        entries = [e for e in entries if e not in drop]
        for name in sorted(drop_names):
            print(f"==> {name}: superseded")

        if not staged and not drop:
            print(f"Nothing to publish in {TAG}.")
            return

        meta = tmp / "meta"
        meta.mkdir()
        packages = "\n\n".join(entries) + "\n"
        (meta / "Packages").write_text(packages)
        with gzip.GzipFile(meta / "Packages.gz", "wb", mtime=0) as gz:
            gz.write(packages.encode())
        release = run("apt-ftparchive",
                      "-o", "APT::FTPArchive::Release::Origin=FreedomNAS",
                      "-o", "APT::FTPArchive::Release::Label=FreedomNAS",
                      "-o", f"APT::FTPArchive::Release::Suite={COMPONENT}",
                      "-o", "APT::FTPArchive::Release::Architectures=amd64 all",
                      "release", ".", capture=True, cwd=meta)
        (meta / "Release").write_text(release)
        key = ["-u", GPG_KEY] if GPG_KEY else []
        run("gpg", "--batch", "--yes", *key, "--clearsign", "-o", str(meta / "InRelease"), str(meta / "Release"))
        run("gpg", "--batch", "--yes", *key, "--armor", "--detach-sign", "-o", str(meta / "Release.gpg"), str(meta / "Release"))
        shutil.copy2(KEYRING, meta / KEYRING.name)

        if DRY_RUN:
            print(f"DRY_RUN: would upload {len(staged)} package(s), the metadata, and delete {len(drop_names)}")
            return
        if staged:
            gh("release", "upload", TAG, *map(str, staged))
        gh("release", "upload", TAG, "--clobber", *(str(meta / m) for m in METADATA))
        for name in sorted(drop_names & published | drop_names & {p.name for p in staged}):
            gh("release", "delete-asset", TAG, name, "--yes")

    print(f"\nPublished {len(staged)} package(s) to {BASE}")


if __name__ == "__main__":
    main()
