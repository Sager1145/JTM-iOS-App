#!/usr/bin/env python3
"""Connect locally restored railway inputs to existing builder paths.

Source downloads live in railway-sources/local and are intentionally not shipped.
This setup command creates only missing aliases; it never replaces real inputs.
"""
import json
import os
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[3]
    catalog = json.loads((root / "railway-sources/catalog.json").read_text())
    linked = missing = 0
    for group in catalog["groups"]:
        original = root / group["legacyPath"]
        local = root / group["localPath"]
        if not local.exists():
            missing += 1
            continue
        if original.is_symlink():
            if original.resolve() != local.resolve():
                raise RuntimeError(f"Existing alias points elsewhere: {original}")
        elif original.exists():
            raise RuntimeError(f"Existing input must be preserved and reviewed: {original}")
        else:
            original.parent.mkdir(parents=True, exist_ok=True)
            original.symlink_to(os.path.relpath(local, original.parent),
                                target_is_directory=local.is_dir())
        linked += 1
    print(f"Local source groups available: {linked}; not restored: {missing}")
    return 0 if linked else 1


if __name__ == "__main__":
    raise SystemExit(main())
