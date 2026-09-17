"""Generate or check source, export, and contributor metadata from release.json."""
import argparse
from pathlib import Path
import re
from release_metadata import ROOT, load_release


def updates(root=ROOT):
    release = load_release(root)
    rules = {
        "project.godot": [(r'(?m)^config/version="[^"]+"$', f'config/version="{release["version"]}"')],
        "src/shared/game_constants.gd": [
            (r'(?m)^const GAME_VERSION: String = .*$', f'const GAME_VERSION: String = "{release["version"]}"'),
            (r'(?m)^const RELEASE_LABEL: String = .*$', f'const RELEASE_LABEL: String = "{release["label"].upper()}"'),
            (r'(?m)^const PROTOCOL_VERSION: int = .*$', f'const PROTOCOL_VERSION: int = {release["protocol_version"]}')],
        "src/shared/network/network_protocol.gd": [
            (r'(?m)^const PACKET_VERSION: int = .*$', f'const PACKET_VERSION: int = {release["packet_version"]}')],
        "docs/DEVELOPMENT.md": [
            (r'(?m)^\| Game version \| .*$', f'| Game version | {release["version"]} |'),
            (r'(?m)^\| Protocol version \| .*$', f'| Protocol version | {release["protocol_version"]} (binary packets {release["packet_version"]}) |')],
    }
    for path, replacements in rules.items():
        original = (root / path).read_text(encoding="utf-8")
        updated = original
        for pattern, replacement in replacements:
            updated, count = re.subn(pattern, lambda _: replacement, updated)
            if count != 1:
                raise ValueError(f"Expected one metadata entry in {path}: {pattern}")
        yield path, original, updated
    path = "export_presets.cfg"
    original = (root / path).read_text(encoding="utf-8")
    blocks = re.split(r"(?=\[preset\.\d+\]\n)", original)
    output = []
    for block in blocks:
        if not block.startswith("[preset."):
            output.append(block)
            continue
        header, options = block.split(".options]", 1)
        server = 'dedicated_server=true' in header
        platform = re.search(r'^platform="([^"]+)"', header, re.M)[1]
        arm = 'binary_format/architecture="arm64"' in options
        stem = f'SuperStarFighter-{release["tag"]}'
        if server:
            if platform == "Windows Desktop":
                name, filename = "Windows Dedicated Server", "server/SuperStarFighter-Server.exe"
            else:
                arch = "arm64" if arm else "x86_64"
                name, filename = f"Linux {arch} Dedicated Server", f"server-linux-{arch}/SuperStarFighter-Server.{arch}"
        elif platform == "Windows Desktop":
            name, filename = f'Windows {release["label"]}', f"{stem}.exe"
        elif platform == "Linux":
            arch = "arm64" if arm else "x86_64"
            name, filename = f'Linux {"ARM64 " if arm else ""}{release["label"]}', f"{stem}.{arch}"
        elif platform == "macOS":
            name, filename = f'macOS {release["label"]}', f"{stem}-macOS-universal.zip"
        else:
            raise ValueError(f"Unsupported export platform: {platform}")
        header = re.sub(r'^name=.*$', f'name="{name}"', header, flags=re.M)
        header = re.sub(r'^export_path=.*$', f'export_path="{release["directory"]}/{filename}"', header, flags=re.M)
        for key in ("file_version", "product_version", "version"):
            options = re.sub(rf'^application/{key}=.*$', f'application/{key}="{release["platform_version"]}"', options, flags=re.M)
        options = re.sub(r'^application/short_version=.*$', f'application/short_version="{release["short_version"]}"', options, flags=re.M)
        output.append(header + ".options]" + options)
    yield path, original, "".join(output)


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
