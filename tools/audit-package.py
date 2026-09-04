#!/usr/bin/env python3
"""Audit the actual embedded Godot 4 PCK against the shipping resource allowlist."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import tempfile
import zipfile

from importlib.machinery import SourceFileLoader

ROOT = Path(__file__).resolve().parents[1]
policy = SourceFileLoader("export_policy", str(ROOT / "tools/update-export-policy.py")).load_module()


def entries(path):
    with path.open("rb") as stream:
        if stream.read(4) == b"GDPC":
            start = 0
        else:
            stream.seek(-12, 2)
            length, magic = struct.unpack("<QI", stream.read(12))
            if magic != 0x43504447:
                raise ValueError("Expected a Godot PCK or embedded PCK footer")
            start = path.stat().st_size - length - 12
        stream.seek(start)
        header = stream.read(40)
        version = struct.unpack_from("<I", header, 4)[0]
        if version != 4:
            raise ValueError(f"Unsupported PCK version {version}; update the auditor explicitly")
        stream.seek(start + struct.unpack_from("<Q", header, 32)[0])

        pack_flags = struct.unpack_from("<I", header, 20)[0]
        file_base = struct.unpack_from("<Q", header, 24)[0] + (start if pack_flags & 2 else 0)
        count = struct.unpack("<I", stream.read(4))[0]
        rows = []
        for _ in range(count):
            size = struct.unpack("<I", stream.read(4))[0]
            name = stream.read(size).rstrip(b"\0").decode("utf-8")
            if not name.startswith("res://"): name = "res://" + name
            offset, length = struct.unpack("<QQ", stream.read(16))
            checksum = stream.read(16).hex()
            flags = struct.unpack("<I", stream.read(4))[0]
            rows.append(dict(path=name, bytes=length, offset=file_base + offset, md5=checksum, flags=flags))
        return rows


def audit(package, server):
    allowed_sources = policy.resources(server)
    allowed = {"res://project.binary", "res://.godot/global_script_class_cache.cfg", "res://.godot/uid_cache.bin"}
    required = set()
    rows = entries(package)
    indexed = {row["path"]: row for row in rows}
    with package.open("rb") as stream:
        for row in rows:
            stream.seek(row["offset"])
            data = stream.read(row["bytes"])
            if len(data) != row["bytes"] or hashlib.md5(data).hexdigest() != row["md5"]:
                raise ValueError(f"Package checksum mismatch: {row['path']}")
            if row["path"].endswith(".remap"):
                row["remap_target"] = re.search(r'path="([^"]+)"', data.decode("utf-8"))[1]
    for source in allowed_sources:
        if source.endswith(".gd"):
            allowed.update([source, source + ".remap", source[:-3] + ".gdc"])
            required.update([source + ".remap", source[:-3] + ".gdc"])
        else:
            import_path = ROOT / (source[6:] + ".import")
            if import_path.exists():
                allowed.add(source + ".import")
                imported = re.findall(r'"(res://\.godot/imported/[^"\n]+)"', import_path.read_text(encoding="utf-8"))
                allowed.update(imported)
                required.add(source + ".import")
            else:
                allowed.update([source, source + ".remap"])
                required.add(source if source in indexed else source + ".remap")
        remap = indexed.get(source + ".remap")
        if remap:
            target = remap["remap_target"]
            # Only permit generated binary resources linked from an allowed
            # source, not arbitrary .godot/exported contents.
            suffix = ".res" if source.endswith(".tres") else ".scn"
            generated = re.fullmatch(r'res://\.godot/exported/\d+/export-[0-9a-f]{32}-' + re.escape(Path(source).stem) + re.escape(suffix), target)
            if target != source[:-3] + ".gdc" and not generated:
                raise ValueError(f"Unexpected remap target: {source} -> {target}")
            allowed.add(target)
            required.add(target)
    names = [row["path"] for row in rows]
    unexpected = sorted(set(names) - allowed)
    missing = sorted(required - set(names))
    if unexpected or missing or len(names) != len(set(names)):
        raise ValueError(f"Package policy failed: unexpected={unexpected[:12]}, missing={missing[:12]}, duplicates={len(names) - len(set(names))}")
    with package.open("rb") as stream:
        sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    result = dict(package=str(package), target="server" if server else "client",
                  executable_bytes=package.stat().st_size,
                  resource_bytes=sum(row["bytes"] for row in rows),
                  entries=len(rows), sha256=sha256,
                  files=rows)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--server", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.package.suffix.lower() == ".zip":
        with zipfile.ZipFile(args.package) as archive, tempfile.TemporaryDirectory() as directory:
            packs = [name for name in archive.namelist() if name.endswith(".pck")]
            if len(packs) != 1:
                raise ValueError("Expected exactly one PCK in the macOS package")
            pack = Path(directory) / "game.pck"
            pack.write_bytes(archive.read(packs[0]))
            result = audit(pack, args.server)
            result["package"] = str(args.package.resolve())
            result["pack_entry"] = packs[0]
    else:
        result = audit(args.package.resolve(), args.server)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"Package audit passed: {result['target']}, {result['entries']} entries, {result['resource_bytes']} resource bytes, SHA256 {result['sha256']}")


if __name__ == "__main__":
    main()
