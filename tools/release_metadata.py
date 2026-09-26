"""Canonical release identity shared by packaging and metadata validation."""
import json
from pathlib import Path
import re
import sys

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


def render(text, release):
    """Replace {{VERSION}}, {{LABEL}}, {{TAG}}, {{PROTOCOL}} and {{PACKET}} in a shipped document."""
    values = {"VERSION": release["version"], "LABEL": release["label"], "TAG": release["tag"],
              "PROTOCOL": str(release["protocol_version"]), "PACKET": str(release["packet_version"])}

    def replace(match):
        if match[1] not in values:
            raise ValueError(f"Unknown release placeholder {match[0]}")
        return values[match[1]]
    return re.sub(r"\{\{(\w+)\}\}", replace, text)


def render_file(source, destination, release=None):
    with open(source, encoding="utf-8", newline="") as stream:
        text = stream.read()
    with open(destination, "w", encoding="utf-8", newline="") as stream:
        stream.write(render(text, release or load_release()))
    return Path(destination)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "render":
        render_file(sys.argv[2], sys.argv[3])
    else:
        print(json.dumps(load_release()))
