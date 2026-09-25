#!/usr/bin/env python3
"""Cross-platform bootstrap, project gate and release packaging (standard library only).

Python counterpart of bootstrap.ps1, verify-foundation.ps1 and the build-*.ps1 scripts,
for Windows, Linux and macOS hosts with or without PowerShell:

  python tools/build.py bootstrap              # pinned Godot editor + export templates
  python tools/build.py verify                 # complete project gate
  python tools/build.py build                  # gate, then every client and server package
  python tools/build.py build windows servers  # gate, then selected targets
"""
import argparse
import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
import urllib.request
import uuid
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_metadata import load_release

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
CACHE = ROOT / ".tools"
DOWNLOADS = CACHE / "downloads"
LOGS = CACHE / "verification-logs"
GODOT_VERSION = "4.7.2-stable"
GODOT_ROOT = CACHE / "godot"
TEMPLATES = GODOT_ROOT / "editor_data" / "export_templates" / "4.7.2.stable"
RELEASE_URL = f"https://github.com/godotengine/godot/releases/download/{GODOT_VERSION}/"
TEMPLATE_ARCHIVE = f"Godot_v{GODOT_VERSION}_export_templates.tpz"
REQUIRED_TEMPLATES = ("windows_release_x86_64.exe", "linux_release.x86_64", "linux_release.arm64", "macos.zip")
AUDIO_EXTENSIONS = (".wav", ".ogg", ".mp3")
CLIENTS = ("windows", "linux-x64", "linux-arm64", "macos")
SERVERS = ("server-windows", "server-linux-x64", "server-linux-arm64")


class GateError(RuntimeError):
    pass


def host():
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}.get(machine, machine)
    return platform.system(), arch


def engine_layout():
    """Return the official editor archive and its executable for this host.

    Self-contained mode keeps editor data beside the engine. On macOS Godot looks for
    `_sc_` beside Godot.app rather than inside the read-only bundle.
    """
    system, arch = host()
    if system == "Windows":
        return f"Godot_v{GODOT_VERSION}_win64.exe.zip", GODOT_ROOT / f"Godot_v{GODOT_VERSION}_win64_console.exe"
    if system == "Linux" and arch in ("x86_64", "arm64"):
        name = f"Godot_v{GODOT_VERSION}_linux.{arch}"
        return f"{name}.zip", GODOT_ROOT / name
    if system == "Darwin":
        return f"Godot_v{GODOT_VERSION}_macos.universal.zip", GODOT_ROOT / "Godot.app/Contents/MacOS/Godot"
    raise GateError(f"Unsupported build host: {system} {arch}")


# ---------------------------------------------------------------- bootstrap

def download(name, force):
    destination = DOWNLOADS / name
    if force or not destination.is_file():
        DOWNLOADS.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {name}...", flush=True)
        partial = destination.with_suffix(destination.suffix + ".part")
        with urllib.request.urlopen(RELEASE_URL + name, timeout=120) as response, partial.open("wb") as stream:
            shutil.copyfileobj(response, stream, 1 << 20)
        partial.replace(destination)
    return destination


def verify_checksum(path, sums):
    rows = [line.split() for line in sums.read_text(encoding="utf-8").splitlines()]
    expected = [row[0].lower() for row in rows if len(row) == 2 and row[1].lstrip("*") == path.name]
    if len(expected) != 1:
        raise GateError(f"No unique official SHA-512 entry was found for {path.name}.")
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha512").hexdigest()
    if actual != expected[0]:
        raise GateError(f"SHA-512 verification failed for {path.name}. Expected {expected[0]}, received {actual}.")
    print(f"Verified {path.name} ({actual[:16]}...)", flush=True)


def extract(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            if not (destination / member.filename).resolve().is_relative_to(root):
                raise GateError(f"Unsafe path in {archive.name}: {member.filename}")
        bundle.extractall(destination)
        if os.name == "posix":
            for member in bundle.infolist():
                mode = (member.external_attr >> 16) & 0o777
                if mode:
                    os.chmod(destination / member.filename, mode)


def bootstrap(force=False):
    archive_name, godot = engine_layout()
    sums = download("SHA512-SUMS.txt", force)
    for name in (archive_name, TEMPLATE_ARCHIVE):
        verify_checksum(download(name, force), sums)
    if force and GODOT_ROOT.exists():
        shutil.rmtree(GODOT_ROOT)
    if not godot.is_file():
        extract(DOWNLOADS / archive_name, GODOT_ROOT)
        godot.chmod(godot.stat().st_mode | 0o111)
    (GODOT_ROOT / "_sc_").touch()
    if not all((TEMPLATES / name).is_file() for name in REQUIRED_TEMPLATES):
        stage = CACHE / "template-stage"
        shutil.rmtree(stage, ignore_errors=True)
        extract(DOWNLOADS / TEMPLATE_ARCHIVE, stage)
        source = next((path for path in stage.rglob("templates") if path.is_dir()), None)
        if source is None:
            raise GateError("The export template archive did not contain a templates directory.")
        shutil.copytree(source, TEMPLATES, dirs_exist_ok=True)
        shutil.rmtree(stage)
    missing = [name for name in REQUIRED_TEMPLATES if not (TEMPLATES / name).is_file()]
    if missing:
        raise GateError(f"Export templates are missing after extraction: {', '.join(missing)}")
    version = subprocess.run([str(godot), "--headless", "--version"], capture_output=True, text=True, timeout=120)
    if version.returncode != 0 or not version.stdout.strip().startswith("4.7.2"):
        raise GateError(f"Unexpected Godot version output: {version.stdout.strip()}")
    print(f"Godot {version.stdout.strip()} and export templates are ready in {GODOT_ROOT}.")
    return godot


def godot_executable(override=None):
    godot = Path(override).resolve() if override else engine_layout()[1]
    if not godot.is_file():
        raise GateError(f"Godot {GODOT_VERSION} is not bootstrapped. Run: python tools/build.py bootstrap")
    return godot


# ---------------------------------------------------------------- verification

def validate(name, output, exit_code, marker="", expected_exit=0, allowed=()):
    """Accept a run only with the expected exit, marker and no unallowlisted errors.

    Engine errors can return zero and still print a passing summary. Script errors are
    never allowlisted; environment allowances match whole lines.
    """
    if exit_code != expected_exit:
        raise GateError(f"{name} exited with {exit_code}; expected {expected_exit}.")
    if marker and not re.search(marker, output, re.IGNORECASE):
        raise GateError(f"{name} did not emit the required completion marker.")
    patterns = (r"^ERROR: Failed to read the root certificate store\.$", *allowed)
    unexpected = []
    for line in output.splitlines():
        line = line.lstrip()
        if line.startswith("SCRIPT ERROR:") or (
                line.startswith("ERROR:") and not any(re.search(p, line, re.IGNORECASE) for p in patterns)):
            unexpected.append(line)
    if unexpected:
        raise GateError(f"{name} emitted unexpected Godot errors: {' | '.join(unexpected)}")


def run_godot(godot, name, args, timeout=1800):
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / f"{re.sub(r'[^a-zA-Z0-9-]', '-', name)}-{uuid.uuid4().hex}.log"
    split = args.index("--") if "--" in args else len(args)
    command = [str(godot), *args[:split], "--log-file", str(log), *args[split:]]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    output = result.stdout.decode("utf-8", "replace")
    log.with_suffix(".console.txt").write_text(output, encoding="utf-8")
    return output, result.returncode, log.with_suffix(".console.txt")


def checked_godot(godot, name, args, marker="", expected_exit=0, allowed=(), timeout=1800):
    output, code, console = run_godot(godot, name, args, timeout)
    try:
        validate(name, output, code, marker, expected_exit, allowed)
    except GateError as error:
        raise GateError(f"{error}\n  Console output: {console}") from None
    print(f"PASS {name}", flush=True)
    return output


def python_tool(*args):
    result = subprocess.run([sys.executable, *map(str, args)], cwd=ROOT)
    if result.returncode != 0:
        raise GateError(f"{Path(str(args[0])).name} failed with exit code {result.returncode}.")


def shipping_policy():
    python_tool(TOOLS / "update-release-metadata.py")
    python_tool(TOOLS / "update-export-policy.py", "--check")
    python_tool(TOOLS / "verify-attribution.py")


def gate_self_test(godot):
    """Prove the acceptance boundary rejects every known false pass."""
    marker = "TEST_SUMMARY passed=1 failed=0"
    validate("gate", marker, 0, r"TEST_SUMMARY passed=\d+ failed=0\b")
    validate("gate", f"ERROR: Failed to read the root certificate store.\n{marker}", 0, marker)
    validate("gate", "EXPECTED_FAILURE", 1, "EXPECTED_FAILURE", expected_exit=1)
    for output, code in (
            (f"ERROR: Typed dictionary lookup failed.\n{marker}", 0),
            (f"SCRIPT ERROR: Failed to read the root certificate store.\n{marker}", 0),
            (f"ERROR: Failed to read the root certificate store. Unexpected extra error\n{marker}", 0),
            (marker, 1),
            ("incomplete run", 0)):
        try:
            validate("gate", output, code, marker)
        except GateError:
            continue
        raise GateError(f"Verification gate accepted an invalid run: {output!r}")
    LOGS.mkdir(parents=True, exist_ok=True)
    fixture = LOGS / f"gate-negative-fixture-{uuid.uuid4().hex}.gd"
    fixture.write_text('extends SceneTree\nfunc _initialize() -> void:\n\tpush_error("SSF_GATE_DELIBERATE_ENGINE_ERROR")\n'
                       f'\tprint("{marker}")\n\tquit(0)\n', encoding="utf-8")
    try:
        output, code, _ = run_godot(godot, "gate-negative-fixture", ["--headless", "--path", str(ROOT), "--script", str(fixture)])
    finally:
        fixture.unlink()
    if code != 0 or marker not in output or not re.search(r"(?m)^ERROR: SSF_GATE_DELIBERATE_ENGINE_ERROR", output):
        raise GateError(f"Engine fixture failed to exercise a zero-exit error: {output}")
    try:
        validate("gate", output, code, marker)
    except GateError as error:
        if "SSF_GATE_DELIBERATE_ENGINE_ERROR" in str(error):
            print("PASS Verification gate: 9 acceptance cases, including a real zero-exit engine error", flush=True)
            return
    raise GateError("Verification gate accepted a real engine error.")


def foundation_gate(godot):
    shipping_policy()
    project = ["--headless", "--path", str(ROOT)]
    checks = [
        ("Editor import and global class registration", ["--headless", "--editor", "--path", str(ROOT), "--quit"], "", 0,
         [r"^ERROR: .*" + re.escape(fragment) + ".*$" for fragment in
          ("Could not open 'user://' directory", "Could not create ObjectDB Snapshots directory: user://")]),
        ("Client startup", [*project, "--quit-after", "5"], "SSF_MODE_READY=client", 0, ()),
    ]
    scripts = sorted(path.relative_to(ROOT).as_posix() for folder in ("src", "tests") for path in (ROOT / folder).rglob("*.gd"))
    checks += [(f"Parse {script}", [*project, "--script", f"res://{script}", "--check-only"], "", 0, ()) for script in scripts]
    checks += [
        ("Server startup and argument parsing",
         [*project, "--quit-after", "5", "--", "--server", "--password=test-lobby", "--port=7123", "--max-players=16", "--rounds-to-win=4"],
         "SSF_MODE_READY=server port=7123 max_players=16 rounds_to_win=4", 0, ()),
        ("Bot-client startup",
         [*project, "--quit-after", "5", "--", "--bot-client=FoundationBot", "--password=test-lobby", "--port=7123"],
         "SSF_MODE_READY=bot_client name=FoundationBot host=127.0.0.1 port=7123", 0, ()),
        ("Passing test suite", [*project, "--", "--run-tests"], "failed=0", 0, ()),
        ("Failing test exit path", [*project, "--", "--run-tests", "--force-test-failure"], "failed=1", 1, ()),
    ]
    for name, args, marker, expected_exit, allowed in checks:
        checked_godot(godot, name, args, re.escape(marker), expected_exit, allowed)
    gate_self_test(godot)
    print(f"Project verification passed ({len(checks) + 1} checks).", flush=True)


# ---------------------------------------------------------------- packaging

def export(godot, preset, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.unlink(missing_ok=True)
    print(f"Exporting {preset}...", flush=True)
    checked_godot(godot, f"Export {preset}", ["--headless", "--path", str(ROOT), "--export-release", preset, str(destination)])
    if not destination.is_file():
        raise GateError(f"{preset} export did not create {destination}.")


def audit(package, report, server=False):
    python_tool(TOOLS / "audit-package.py", package, *(["--server"] if server else []), "--output", report)


def write_zip(archive, entries):
    """Write (name, source, executable) entries with Unix modes so Linux binaries stay runnable."""
    archive.unlink(missing_ok=True)
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, source, executable in entries:
            info = zipfile.ZipInfo.from_file(source, name)
            info.create_system = 3
            info.external_attr = (0o100755 if executable else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(source, "rb") as stream, bundle.open(info, "w") as target:
                shutil.copyfileobj(stream, target, 1 << 20)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise GateError(f"Archive verification failed: {archive}")


def client_documents(linux=False):
    suffix = "-LINUX" if linux else ""
    return [(f"README-BETA{suffix}.txt", ROOT / "docs/BETA_README.txt", False),
            (f"THIRD-PARTY-NOTICES{suffix}.txt", ROOT / "docs/THIRD_PARTY_NOTICES.txt", False),
            ("GODOT_COPYRIGHT.txt", ROOT / "docs/GODOT_COPYRIGHT.txt", False),
            ("LICENSE.txt", ROOT / "LICENSE", False),
            ("ASSET-LICENSE.txt", ROOT / "assets/LICENSE.md", False)]


def can_run(system, arch, display=False):
    host_system, host_arch = host()
    if (host_system, host_arch) != (system, arch):
        return False
    return not display or system != "Linux" or bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def expected_music():
    music = ROOT / "assets/audio/music"
    def audio(folder):
        return [path.name.lower() for path in folder.iterdir() if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS] if folder.is_dir() else []
    root = audio(music)
    return (int(any(name.startswith("main_menu.") for name in root)), len(audio(music / "gameplay")),
            int(any(name.startswith("win.") for name in root)))


def smoke_client(binary, log):
    print(f"Launching {binary.name} through its normal rendered startup path...", flush=True)
    log.unlink(missing_ok=True)
    result = subprocess.run([str(binary), "--audio-driver", "Dummy", "--resolution", "1280x720", "--position", "-10000,-10000",
                             "--quit-after", "5", "--log-file", str(log)],
                            cwd=binary.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    if not log.is_file():
        raise GateError("Exported client smoke test did not create its log.")
    text = log.read_text(encoding="utf-8", errors="replace")
    validate("Exported client smoke", text, result.returncode, "SSF_MODE_READY=client")
    found = re.search(r"SSF_AUDIO_READY menu=(\d+) gameplay=(\d+) win=(\d+)", text)
    if not found:
        raise GateError("Exported client did not report its authored music inventory.")
    exported, source = tuple(map(int, found.groups())), expected_music()
    if exported != source:
        raise GateError(f"Exported music inventory mismatch (menu, gameplay, win): source={source}, export={exported}.")
    print(f"PASS Exported client smoke and music inventory {exported}", flush=True)


def smoke_server(binary, log, extra=()):
    log.unlink(missing_ok=True)
    # Run outside the source tree without --path or --server: the artifact must select
    # server mode and resolve its own embedded resources independently.
    result = subprocess.run([str(binary), *extra, "--log-file", str(log), "--", "--password=export-smoke", "--port=17820",
                             "--test-server-duration=2"],
                            cwd=binary.parent, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    validate("Standalone server smoke", text, result.returncode, "SSF_MODE_READY=server")
    if "SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration" not in text:
        raise GateError("Standalone server smoke did not shut down gracefully.")
    print("PASS Standalone server smoke", flush=True)


def windows_version_present(data, version):
    value = version.encode("utf-16-le")
    for key in ("FileVersion", "ProductVersion"):
        pattern = f"{key}\0".encode("utf-16-le")
        found, start = False, data.find(pattern)
        while start >= 0 and not found:
            end = start + len(pattern)
            found = data.find(value, end, end + 4 + len(value)) >= 0
            start = data.find(pattern, end)
        if not found:
            return False
    return True


def build_windows(godot, release, output):
    client = output / f"SuperStarFighter-{release['tag']}.exe"
    export(godot, f"Windows {release['label']}", client)
    audit(client, output / "client-package-audit.json")
    if not windows_version_present(client.read_bytes(), release["platform_version"]):
        raise GateError(f"Exported Windows file/product version is not {release['platform_version']}.")
    print(f"PASS Windows metadata {release['platform_version']}", flush=True)
    if can_run("Windows", "x86_64"):
        smoke_client(client, output / "beta-smoke.log")
    else:
        print("SKIP Launch smoke: requires a Windows x64 host.")
    archive = output / f"SuperStarFighter-{release['tag']}-Windows-x64.zip"
    write_zip(archive, [(client.name, client, True), *client_documents()])
    return [archive]


def build_linux(godot, release, output, arch):
    arm = arch == "arm64"
    client = output / f"SuperStarFighter-{release['tag']}.{arch}"
    export(godot, f"Linux {'ARM64 ' if arm else ''}{release['label']}", client)
    audit(client, output / f"linux-{arch}-package-audit.json")
    data = client.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1 or data[18:20] != bytes([0xB7 if arm else 0x3E, 0]):
        raise GateError(f"Linux export is not a little-endian 64-bit {arch} ELF executable.")
    if release["version"].encode() not in data:
        raise GateError(f"Linux export does not contain the packaged version {release['version']}.")
    print(f"PASS Linux {arch} ELF header and embedded version", flush=True)
    if can_run("Linux", arch, display=True):
        smoke_client(client, output / f"linux-{arch}-smoke.log")
    else:
        print(f"SKIP Launch smoke: requires a Linux {arch} host with a display.")
    archive = output / f"SuperStarFighter-{release['tag']}-Linux-{'arm64' if arm else 'x64'}.zip"
    write_zip(archive, [(client.name, client, True), *client_documents(linux=True)])
    return [archive]


def entry_contains(bundle, entry, text):
    needle, tail = text.encode(), b""
    with bundle.open(entry) as stream:
        while chunk := stream.read(1 << 20):
            if needle in tail + chunk:
                return True
            tail = (tail + chunk)[-(len(needle) - 1):]
    return False


def build_macos(godot, release, output):
    archive = output / f"SuperStarFighter-{release['tag']}-macOS-universal.zip"
    export(godot, f"macOS {release['label']}", archive)
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        executable = next((e for e in entries if re.search(r"\.app/Contents/MacOS/[^/]+$", e.filename)), None)
        plist = next((e for e in entries if re.search(r"\.app/Contents/Info\.plist$", e.filename)), None)
        if not executable or not plist:
            raise GateError("macOS export is missing its app executable or Info.plist.")
        if ((executable.external_attr >> 16) & 0o111) != 0o111:
            raise GateError("macOS app executable is missing Unix execute permissions.")
        header = bundle.open(executable).read(72)
        magic, count = int.from_bytes(header[0:4], "big"), int.from_bytes(header[4:8], "big")
        if magic not in (0xCAFEBABE, 0xCAFEBABF):
            raise GateError(f"macOS app executable is not a universal Mach-O binary (magic=0x{magic:08X}).")
        size = 32 if magic == 0xCAFEBABF else 20
        if count < 2 or len(header) < 8 + count * size:
            raise GateError("macOS app executable does not contain a valid two-architecture Mach-O table.")
        cpus = {int.from_bytes(header[8 + i * size:12 + i * size], "big") for i in range(count)}
        if not {0x01000007, 0x0100000C} <= cpus:
            raise GateError("macOS app executable does not contain both x86_64 and arm64 slices.")
        plist_text = bundle.read(plist).decode("utf-8", "replace")
        if "com.dumpsterfirelabs.superstarfighter" not in plist_text or release["platform_version"] not in plist_text:
            raise GateError("macOS Info.plist does not contain the expected bundle identifier and version.")
        if not any(re.search(r"\.app/Contents/(MacOS|Resources)/", e.filename) and entry_contains(bundle, e, release["version"])
                   for e in entries):
            raise GateError(f"macOS export does not contain the packaged version {release['version']}.")
        existing = set(bundle.namelist())
    documents = [(name, source) for name, source, _ in client_documents()]
    if existing & {name for name, _ in documents}:
        raise GateError("macOS export unexpectedly already contains release documents.")
    with zipfile.ZipFile(archive, "a", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, source in documents:
            info = zipfile.ZipInfo.from_file(source, name)
            info.create_system, info.external_attr, info.compress_type = 3, 0o100644 << 16, zipfile.ZIP_DEFLATED
            bundle.writestr(info, source.read_bytes())
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise GateError("macOS archive verification failed.")
    print("PASS macOS app bundle, metadata, universal Mach-O and embedded version", flush=True)
    audit(archive, output / "macos-package-audit.json")
    print("NOTE Runtime launch, code signing and notarization must be verified on a macOS host.")
    return [archive]


def build_windows_server(godot, release, output):
    folder = output / "server"
    server = folder / "SuperStarFighter-Server.exe"
    export(godot, "Windows Dedicated Server", server)
    audit(server, folder / "package-audit.json", server=True)
    payload = [(ROOT / "docs" / name, name) for name in ("THIRD_PARTY_NOTICES.txt", "GODOT_COPYRIGHT.txt", "SERVER_README.txt")]
    payload += [(ROOT / "LICENSE", "LICENSE.txt"), (TOOLS / "start-server.ps1", "start-server.ps1"), (TOOLS / "admin.ps1", "admin.ps1")]
    for source, name in payload:
        shutil.copyfile(source, folder / name)
    if can_run("Windows", "x86_64"):
        smoke_server(server, folder / "server-smoke.log")
        shell = shutil.which("pwsh") or shutil.which("powershell")
        if shell:
            result = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-File", str(TOOLS / "verify-server-operations.ps1"),
                                     "-ServerExecutable", str(server)], cwd=ROOT)
            if result.returncode != 0:
                raise GateError("Dedicated server operations verification failed.")
        else:
            print("SKIP Launcher/admin operations check: requires PowerShell to run the packaged .ps1 tools.")
    else:
        print("SKIP Server smoke: requires a Windows x64 host.")
    archive = folder / f"SuperStarFighter-{release['tag']}-Server-Windows-x64.zip"
    write_zip(archive, [(server.name, server, True), *[(name, folder / name, False) for _, name in payload]])
    return [archive]


def build_linux_server(godot, release, output, arch):
    folder = output / f"server-linux-{arch}"
    server = folder / f"SuperStarFighter-Server.{arch}"
    export(godot, f"Linux {arch} Dedicated Server", server)
    audit(server, folder / "package-audit.json", server=True)
    if can_run("Linux", arch):
        smoke_server(server, folder / "server-smoke.log", extra=("--headless",))
    else:
        print(f"SKIP Server smoke: requires a Linux {arch} host.")
    python_tool(TOOLS / "package-linux-server.py", arch, folder)
    label = "x64" if arch == "x86_64" else "arm64"
    return [folder / f"SuperStarFighter-{release['tag']}-Server-Linux-{label}{suffix}" for suffix in (".tar.gz", ".zip")]


TARGETS = {
    "windows": build_windows,
    "linux-x64": lambda godot, release, output: build_linux(godot, release, output, "x86_64"),
    "linux-arm64": lambda godot, release, output: build_linux(godot, release, output, "arm64"),
    "macos": build_macos,
    "server-windows": build_windows_server,
    "server-linux-x64": lambda godot, release, output: build_linux_server(godot, release, output, "x86_64"),
    "server-linux-arm64": lambda godot, release, output: build_linux_server(godot, release, output, "arm64"),
}
GROUPS = {"all": CLIENTS + SERVERS, "clients": CLIENTS, "servers": SERVERS}


def write_checksums(output, archives):
    """Merge archive digests into one SHA256SUMS.txt for the release directory."""
    sums = output / "SHA256SUMS.txt"
    digests = {}
    if sums.is_file():
        for line in sums.read_text(encoding="utf-8").splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2:
                digests[parts[1].lstrip("*")] = parts[0]
    for archive in archives:
        with archive.open("rb") as stream:
            digests[archive.name] = hashlib.file_digest(stream, "sha256").hexdigest()
    sums.write_text("".join(f"{digest}  {name}\n" for name, digest in sorted(digests.items())), encoding="utf-8")
    return sums, digests


def build(godot, targets, output, skip_gate):
    release = load_release()
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    version = re.search(r'config/version="([^"]+)"', project)
    if not version or version.group(1) != release["version"]:
        raise GateError(f"Project version must be {release['version']} before producing {release['label']}.")
    if skip_gate:
        shipping_policy()
    else:
        print("Running the complete project gate before export...", flush=True)
        foundation_gate(godot)
    output.mkdir(parents=True, exist_ok=True)
    archives = []
    for target in targets:
        print(f"\n== {target} ==", flush=True)
        archives += TARGETS[target](godot, release, output)
    sums, digests = write_checksums(output, archives)
    print(f"\n{release['label']} packages ({output}):")
    for archive in archives:
        print(f"  {archive.relative_to(output).as_posix()}  sha256={digests[archive.name]}")
    print(f"Checksums: {sums}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("bootstrap", help="download and verify the pinned Godot editor and export templates")
    setup.add_argument("--force", action="store_true", help="re-download and re-extract everything")
    verify = commands.add_parser("verify", help="run the complete project gate")
    package = commands.add_parser("build", help="run the gate, then export, verify and package targets")
    package.add_argument("targets", nargs="*", default=["all"], metavar="TARGET",
                         help=f"one or more of: {', '.join([*GROUPS, *TARGETS])} (default: all)")
    package.add_argument("--skip-gate", action="store_true", help="skip the project gate (shipping-policy checks still run)")
    package.add_argument("--output", type=Path, help="output directory (default: the release directory from release.json)")
    for command in (verify, package):
        command.add_argument("--godot", help="use this Godot 4.7.2 editor instead of the bootstrapped one")
    args = parser.parse_args()
    try:
        if args.command == "bootstrap":
            bootstrap(args.force)
        elif args.command == "verify":
            foundation_gate(godot_executable(args.godot))
        else:
            unknown = [t for t in args.targets if t not in TARGETS and t not in GROUPS]
            if unknown:
                parser.error(f"unknown target(s): {', '.join(unknown)}")
            targets = list(dict.fromkeys(t for name in args.targets for t in GROUPS.get(name, (name,))))
            output = (args.output or ROOT / load_release()["directory"]).resolve()
            build(godot_executable(args.godot), targets, output, args.skip_gate)
    except (GateError, subprocess.TimeoutExpired) as error:
        print(f"\nFAILED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
