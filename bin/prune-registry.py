#!/usr/bin/env python3
"""Delete old package versions from Codeberg's registry, to stay within quota.

    CODEBERG_USER=<user> CODEBERG_TOKEN=<token> bin/prune-registry.py
    DRY_RUN=1 bin/prune-registry.py

Every package keeps its KEEP newest snapshots (1.0+<date>...) and its KEEP
newest releases, counted apart so snapshots never push a release out.
Kernels are named after their release (linux-image-<kver>,
linux-headers-<kver>), one package per kernel: the KEEP newest kernels stay,
older ones go with their headers.
"""
import base64
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from collections import defaultdict

OWNER = os.environ.get("CODEBERG_OWNER", "FreedomNAS")
TYPE = os.environ.get("REGISTRY_TYPE", "debian")
KEEP = int(os.environ.get("KEEP", "2"))
DRY_RUN = bool(os.environ.get("DRY_RUN"))
API = f"https://codeberg.org/api/v1/packages/{OWNER}"

KERNEL = re.compile(r"^linux-(?:image|headers)-(\d.*)$")
SNAPSHOT = re.compile(r"\+\d{8}")


def request(url, method="GET"):
    req = urllib.request.Request(url, method=method)
    if method != "GET":
        credentials = f"{os.environ['CODEBERG_USER']}:{os.environ['CODEBERG_TOKEN']}"
        req.add_header("Authorization", "Basic " + base64.b64encode(credentials.encode()).decode())
    with urllib.request.urlopen(req) as response:
        return json.load(response) if method == "GET" else None


def packages():
    page = 1
    while batch := request(f"{API}?type={TYPE}&limit=50&page={page}"):
        yield from batch
        page += 1


def doomed(all_packages):
    groups = defaultdict(list)
    kernels = defaultdict(list)
    for package in all_packages:
        kernel = KERNEL.match(package["name"])
        if kernel:
            kernels[kernel.group(1)].append(package)
            continue
        snapshot = bool(SNAPSHOT.search(package["version"]))
        groups[(package["name"], snapshot)].append(package)

    for versions in groups.values():
        versions.sort(key=lambda p: p["created_at"], reverse=True)
        yield from versions[KEEP:]

    newest_first = sorted(kernels.values(), key=lambda ps: max(p["created_at"] for p in ps), reverse=True)
    for old_kernel in newest_first[KEEP:]:
        yield from old_kernel


def main():
    if not DRY_RUN:
        for variable in ("CODEBERG_USER", "CODEBERG_TOKEN"):
            if not os.environ.get(variable):
                sys.exit(f"prune-registry.py: set {variable}")
    removed = 0
    for package in doomed(list(packages())):
        name, version = package["name"], package["version"]
        print(f"==> {'would delete' if DRY_RUN else 'deleting'} {name} {version}")
        if not DRY_RUN:
            request(f"{API}/{TYPE}/{urllib.parse.quote(name, safe='')}/{urllib.parse.quote(version, safe='')}", "DELETE")
        removed += 1
    print(f"{removed} version(s) {'to delete' if DRY_RUN else 'deleted'}, keeping {KEEP} of each")


if __name__ == "__main__":
    main()
