#!/usr/bin/env python3
"""Check asset inventory coverage and integrity without inventing licensing evidence."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-resolved", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "docs/asset-provenance.json").read_text(encoding="utf-8"))
    actual = {p.relative_to(ROOT).as_posix() for p in (ROOT / "assets").rglob("*")
              if p.is_file() and p.suffix.lower() not in {".import", ".md"} and p.name != ".gitkeep"}
    recorded = {row["path"] for row in manifest["assets"]}
    if actual != recorded or len(recorded) != len(manifest["assets"]):
        raise SystemExit(f"Asset inventory coverage mismatch: new={sorted(actual-recorded)}, removed={sorted(recorded-actual)}")
    pending = []
    for row in manifest["assets"]:
        with (ROOT / row["path"]).open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if digest != row["sha256"]:
            raise SystemExit(f"Asset changed; review and update its provenance record: {row['path']}")
        if not row["evidence"] or not row["distribution_status"]:
            raise SystemExit(f"Incomplete inventory record: {row['path']}")
        if row["distribution_status"].endswith("_needed"):
            pending.append(row["path"])
    notices = (ROOT / "docs/GODOT_COPYRIGHT.txt").read_text(encoding="utf-8")
    if "COMPONENT:" not in notices or "LICENSE:" not in notices or "Godot 4.7.2" not in notices:
        raise SystemExit("Engine component notices are missing or stale.")
    print(f"Attribution inventory verified: {len(recorded)} assets; {len(pending)} need provenance resolution.")
    if args.require_resolved and pending:
        raise SystemExit("Unresolved provenance: " + ", ".join(pending))


if __name__ == "__main__":
    main()
