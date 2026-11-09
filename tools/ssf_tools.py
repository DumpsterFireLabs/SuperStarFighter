"""Facts and helpers shared by the Python tool scripts.

The pinned engine version lives in tools/engine.json, which tools/common.ps1
also reads. The Godot output gate here is the Python twin of
Assert-SsfGodotResult in tools/common.ps1; keep the two in step.
"""
import json
import platform
import re
import subprocess
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".tools"
LOGS = CACHE / "verification-logs"
GODOT_ROOT = CACHE / "godot"

_ENGINE = json.loads((ROOT / "tools" / "engine.json").read_text(encoding="utf-8"))
GODOT_RELEASE = _ENGINE["godot"]                       # 4.7.2
GODOT_VERSION = f"{GODOT_RELEASE}-{_ENGINE['status']}"  # 4.7.2-stable, the release tag
TEMPLATE_VERSION = f"{GODOT_RELEASE}.{_ENGINE['status']}"  # 4.7.2.stable, the template folder

# The one engine diagnostic every gate tolerates: Windows runners without a
# readable certificate store print it on startup.
DEFAULT_ALLOWED_ERRORS = (r"^ERROR: Failed to read the root certificate store\.$",)


class GateError(RuntimeError):
    pass


def host():
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "aarch64": "arm64", "arm64": "arm64"}.get(machine, machine)
    return platform.system(), arch


def engine_layout(root=GODOT_ROOT):
    """Return the official editor archive name and its executable for this host.

    Self-contained mode keeps editor data beside the engine. On macOS Godot looks for
    `_sc_` beside Godot.app rather than inside the read-only bundle.
    """
    system, arch = host()
    if system == "Windows":
        return f"Godot_v{GODOT_VERSION}_win64.exe.zip", root / f"Godot_v{GODOT_VERSION}_win64_console.exe"
    if system == "Linux" and arch in ("x86_64", "arm64"):
        name = f"Godot_v{GODOT_VERSION}_linux.{arch}"
        return f"{name}.zip", root / name
    if system == "Darwin":
        return f"Godot_v{GODOT_VERSION}_macos.universal.zip", root / "Godot.app/Contents/MacOS/Godot"
    raise GateError(f"Unsupported build host: {system} {arch}")


def default_godot():
    """The bootstrapped editor for this host, for use as an argparse default."""
    return engine_layout()[1]


def godot_executable(override=None):
    godot = Path(override).resolve() if override else default_godot()
    if not godot.is_file():
        raise GateError(f"Godot {GODOT_VERSION} is not bootstrapped. Run: python tools/build.py bootstrap")
    return godot


def unexpected_errors(output, allowed=()):
    """Return the engine and script error lines a gate must reject.

    Script errors are never allowlisted; engine errors are accepted only when a
    whole line matches an allowed pattern.
    """
    patterns = (*DEFAULT_ALLOWED_ERRORS, *allowed)
    unexpected = []
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("SCRIPT ERROR:") or (
                line.startswith("ERROR:") and not any(re.search(p, line, re.IGNORECASE) for p in patterns)):
            unexpected.append(line)
    return unexpected


def validate_godot_output(name, output, exit_code, marker="", expected_exit=0, allowed=()):
    """Accept a run only with the expected exit, marker and no unallowlisted errors.

    Engine errors can return zero and still print a passing summary, so the exit
    code alone is never enough.
    """
    if exit_code != expected_exit:
        raise GateError(f"{name} exited with {exit_code}; expected {expected_exit}.")
    if marker and not re.search(marker, output, re.IGNORECASE):
        raise GateError(f"{name} did not emit the required completion marker.")
    unexpected = unexpected_errors(output, allowed)
    if unexpected:
        raise GateError(f"{name} emitted unexpected Godot errors: {' | '.join(unexpected)}")


def run_godot(godot, name, args, timeout=1800):
    """Run Godot with a unique log file; return (console output, exit code, console path)."""
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / f"{re.sub(r'[^a-zA-Z0-9-]', '-', name)}-{uuid.uuid4().hex}.log"
    split = args.index("--") if "--" in args else len(args)
    command = [str(godot), *args[:split], "--log-file", str(log), *args[split:]]
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    output = result.stdout.decode("utf-8", "replace")
    log.with_suffix(".console.txt").write_text(output, encoding="utf-8")
    return output, result.returncode, log.with_suffix(".console.txt")
