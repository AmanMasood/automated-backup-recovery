#!/usr/bin/env python3
"""Report on backup sets and alert when the newest one is too old or broken.

Exit codes: 0 OK, 1 stale/missing backups, 2 newest set fails checksum.
    backup_report.py --root /var/backups/app --max-age-hours 26 [--json]
"""
import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_set(path: str) -> bool:
    sums = os.path.join(path, "SHA256SUMS")
    if not os.path.exists(sums):
        return False
    with open(sums) as fh:
        for line in fh:
            digest, name = line.split(maxsplit=1)
            target = os.path.join(path, name.strip().lstrip("*"))
            if not os.path.exists(target) or sha256(target) != digest:
                return False
    return True


def scan(root: str) -> list:
    sets = []
    if not os.path.isdir(root):
        return sets
    for name in sorted(os.listdir(root), reverse=True):
        full = os.path.join(root, name)
        if not (os.path.isdir(full) and name.startswith("20")):
            continue
        files = [f for f in os.listdir(full) if f.endswith(".gz")]
        size = sum(os.path.getsize(os.path.join(full, f)) for f in files)
        try:
            created = datetime.strptime(name, "%Y-%m-%d_%H%M%S").timestamp()
        except ValueError:
            created = os.path.getmtime(full)
        sets.append({"name": name, "files": len(files), "bytes": size,
                     "age_hours": round((time.time() - created) / 3600, 2)})
    return sets


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=os.environ.get("BACKUP_ROOT", "/var/backups/app"))
    ap.add_argument("--max-age-hours", type=float, default=26)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    sets = scan(args.root)
    status, code = "ok", 0
    if not sets:
        status, code = "no backups found", 1
    elif sets[0]["age_hours"] > args.max_age_hours:
        status, code = f"newest backup is {sets[0]['age_hours']}h old", 1
    elif not check_set(os.path.join(args.root, sets[0]["name"])):
        status, code = "newest backup failed checksum verification", 2

    report = {"root": args.root, "status": status, "count": len(sets),
              "total_bytes": sum(s["bytes"] for s in sets), "sets": sets}
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Backups in {args.root}: {len(sets)}  status: {status}")
        for s in sets:
            print(f"  {s['name']}  {s['files']} file(s)  {s['bytes'] / 1024:.1f} KiB  {s['age_hours']}h old")
    return code


if __name__ == "__main__":
    sys.exit(main())
