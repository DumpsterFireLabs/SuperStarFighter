#!/usr/bin/env python3
"""Generate explicit resource allowlists before Godot's script compilation pass."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SHARED = ("src/shared", "src/server", "scenes/server", "scenes/bootstrap", "data/cards", "resources/maps")
CLIENT = ("src/client", "scenes/client", "scenes/gameplay", "assets")
RESOURCE_EXTENSIONS = {".gd", ".tscn", ".tres", ".png", ".svg", ".wav", ".ogg", ".mp3"}


def resources(server):
    result = {"res://src/bootstrap.gd"}
    for directory in SHARED + (() if server else CLIENT):
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and path.suffix in RESOURCE_EXTENSIONS:
                result.add("res://" + path.relative_to(ROOT).as_posix())
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = ROOT / "export_presets.cfg"
    original = path.read_text(encoding="utf-8")
    blocks = re.split(r"(?=\[preset\.\d+\]\n)", original)
    result = []
    for block in blocks:
        if not block.startswith("[preset."):
            result.append(block)
            continue
        header, options = block.split(".options]", 1)
        files = resources('dedicated_server=true' in header)
        header = re.sub(r'^export_filter=.*$', 'export_filter="resources"', header, flags=re.M)
        header = re.sub(r'^export_files=.*\n', '', header, flags=re.M)
        line = 'export_files=PackedStringArray(' + ', '.join('"' + name + '"' for name in files) + ')\n'
        header = header.replace('export_filter="resources"\n', 'export_filter="resources"\n' + line)
        result.append(header + '.options]' + options)
    updated = ''.join(result).rstrip() + '\n'
    if args.check:
        if updated != original:
            raise SystemExit("Shipping resource lists are stale. Run python tools/update-export-policy.py")
        print("Shipping resource allowlists are current.")
    else:
        path.write_text(updated, encoding="utf-8", newline="\n")
        print(f"Updated client ({len(resources(False))}) and server ({len(resources(True))}) resource allowlists.")


if __name__ == "__main__":
    main()
