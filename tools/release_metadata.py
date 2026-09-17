"""Canonical release identity shared by packaging and metadata validation."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def load_release(root=ROOT):
    release = json.loads((root / "release.json").read_text(encoding="utf-8"))
    match = re.fullmatch(r"(\d+\.\d+\.\d+)-beta\.(\d+)", release["version"])
    if not match:
        raise ValueError("Expected a version such as 0.1.0-beta.12")
    base, beta = match.groups()
    for key in ("protocol_version", "packet_version"):
        if type(release[key]) is not int or release[key] < 1:
            raise ValueError(f"{key} must be a positive integer")
    return dict(release, short_version=base, platform_version=f"{base}.{beta}",
                label=f"Beta {beta}", tag=f"Beta{beta}", directory=f"builds/beta-{beta}")


if __name__ == "__main__":
    print(json.dumps(load_release()))
