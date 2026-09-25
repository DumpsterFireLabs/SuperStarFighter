"""Package and statically verify a Linux dedicated server export."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tarfile
import zipfile
from release_metadata import load_release

release = load_release()

root = Path(__file__).resolve().parents[1]
arch = sys.argv[1]
assert arch in ("x86_64", "arm64")
build = root / f"{release['directory']}/server-linux-{arch}"
binary = build / f"SuperStarFighter-Server.{arch}"
data = binary.read_bytes()
assert data[:6] == b"\x7fELF\x02\x01"
assert struct.unpack_from("<H", data, 18)[0] == (62 if arch == "x86_64" else 183)
assert release["version"].encode() in data
files = {binary.name: binary}
for name in ("SERVER_README.txt", "THIRD_PARTY_NOTICES.txt", "GODOT_COPYRIGHT.txt"):
    files[name] = root / "docs" / name
files["LICENSE.txt"] = root / "LICENSE"
for name in ("start-server.sh", "admin.py"):
    files[name] = root / "tools" / name
label = "x64" if arch == "x86_64" else "arm64"
base = build / f"SuperStarFighter-{release['tag']}-Server-Linux-{label}"
for name, source in files.items():
    if source != build / name:
        (build / name).write_bytes(source.read_bytes())
def mode(name):
    return 0o755 if name in (binary.name, "start-server.sh", "admin.py") else 0o644
with tarfile.open(str(base) + ".tar.gz", "w:gz") as archive:
    for name in files:
        path = build / name
        info = archive.gettarinfo(str(path), arcname=name)
        info.mode = mode(name)
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        with path.open("rb") as stream:
            archive.addfile(info, stream)
with zipfile.ZipFile(str(base) + ".zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        info = zipfile.ZipInfo(name)
        info.create_system = 3
        info.external_attr = (0o100000 | mode(name)) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, (build / name).read_bytes())
with tarfile.open(str(base) + ".tar.gz") as archive:
    assert set(archive.getnames()) == set(files)
    for entry in archive:
        assert entry.mode == mode(entry.name)
        assert archive.extractfile(entry).read() == files[entry.name].read_bytes()
with zipfile.ZipFile(str(base) + ".zip") as archive:
    assert archive.testzip() is None
    assert set(archive.namelist()) == set(files)
    for name in files:
        assert archive.read(name) == files[name].read_bytes()
artifacts = []
for suffix in (".tar.gz", ".zip"):
    path = Path(str(base) + suffix)
    artifacts.append(dict(name=path.name, bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(build / "SHA256SUMS.txt").write_text("".join(f"{a['sha256']}  {a['name']}\n" for a in artifacts))
manifest = dict(version=release["version"], architecture=arch, elf_and_archive_checks_passed=True, native_runtime_tested=False, artifacts=artifacts)
(build / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
