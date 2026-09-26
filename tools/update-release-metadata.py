"""Generate or check source and export metadata from release.json."""
import argparse
from pathlib import Path
import re
from release_metadata import ROOT, load_release


def updates(root=ROOT):
    release = load_release(root)
    platform = f'"{release["platform_version"]}"'
    rules = {
        "project.godot": [(r'(?m)^config/version="[^"]+"$', f'config/version="{release["version"]}"')],
        "src/shared/game_constants.gd": [
            (r'(?m)^const PROTOCOL_VERSION: int = .*$', f'const PROTOCOL_VERSION: int = {release["protocol_version"]}')],
        "src/shared/network/network_protocol.gd": [
            (r'(?m)^const PACKET_VERSION: int = .*$', f'const PACKET_VERSION: int = {release["packet_version"]}')],
        # Preset names and export paths are version-free; only embedded platform metadata carries the release.
        "export_presets.cfg": [
            (r'(?m)^application/(file_version|product_version|version)=.*$', lambda m: f"application/{m[1]}={platform}"),
            (r'(?m)^application/short_version=.*$', f'application/short_version="{release["short_version"]}"')],
    }
    for path, replacements in rules.items():
        original = (root / path).read_text(encoding="utf-8")
        updated = original
        for pattern, replacement in replacements:
            updated, count = re.subn(pattern, replacement if callable(replacement) else lambda _: replacement, updated)
            if count < 1:
                raise ValueError(f"Expected metadata entry in {path}: {pattern}")
        yield path, original, updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Update generated metadata; default checks without writing")
    args = parser.parse_args()
    stale = []
    for path, original, updated in updates():
        if updated == original:
            continue
        stale.append(path)
        if args.write:
            (ROOT / path).write_text(updated, encoding="utf-8", newline="\n")
    if stale and not args.write:
        raise SystemExit("Release metadata is stale: " + ", ".join(stale) + ". Run python tools/update-release-metadata.py --write")
    print("Release metadata updated." if args.write else "Release metadata is current.")


if __name__ == "__main__":
    main()
