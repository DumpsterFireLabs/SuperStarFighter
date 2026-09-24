"""Retain compact review measurements and the exact source hashes they describe."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

def run(*args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    return {"exit_code": result.returncode, "output": result.stdout + result.stderr}

def markers(path):
    rows = {}
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if line.startswith("SSF_") and "={" in line:
            name, value = line.split("=", 1)
            rows[name] = json.loads(value)
        elif line.startswith("SSF_PERFORMANCE_") or line.startswith("SSF_MINE_PERFORMANCE_"):
            rows[line.split(" ", 1)[0]] = line
    return rows

data = {
    "review_date": "2026-09-22",
    "head": run("git", "rev-parse", "HEAD")["output"].strip(),
    "working_tree": run("git", "status", "--short")["output"],
    "source_sha256": {},
    "performance": markers(ROOT / ".tools/review-2026-09-22-performance.log"),
    "rendered": markers(ROOT / ".tools/review-2026-09-22-frames-retry.log"),
    "draw_cpu_attribution": markers(ROOT / ".tools/review-2026-09-22-draw.log"),
    "probes": markers(ROOT / ".tools/review-2026-09-22-probes.log"),
    "release_checks": {
        "metadata": run("python", "tools/update-release-metadata.py"),
        "export_policy": run("python", "tools/update-export-policy.py", "--check"),
        "unit": run("python", "-m", "unittest", "discover", "-s", "tools", "-p", "test_release_metadata.py"),
        "attribution": run("python", "tools/verify-attribution.py"),
    },
}
for directory in ["src", "tests", "data/cards", "resources/maps"]:
    for path in sorted((ROOT / directory).rglob("*")):
        if path.is_file() and path.suffix in {".gd", ".tres"}:
            data["source_sha256"][path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
for name in ["project.godot", "release.json", "export_presets.cfg", "docs/review-evidence-2026-09-22/review_probe.gd", "docs/review-evidence-2026-09-22/draw_attribution.gd", "docs/review-evidence-2026-09-22/collect_evidence.py"]:
    data["source_sha256"][name] = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()

spec = importlib.util.spec_from_file_location("export_policy", ROOT / "tools/update-export-policy.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
data["export_differences"] = []
for block in re.split(r"(?=\[preset\.\d+\]\n)", (ROOT / "export_presets.cfg").read_text(encoding="utf-8")):
    if not block.startswith("[preset."):
        continue
    header = block.split(".options]", 1)[0]
    current = set(re.findall(r'"(res://[^"]+)"', re.search(r"^export_files=.*$", header, re.M)[0]))
    expected = set(module.resources("dedicated_server=true" in header))
    data["export_differences"].append({"name": re.search(r'^name="([^"]+)"', header, re.M)[1], "missing": sorted(expected - current), "obsolete": sorted(current - expected)})

net = ROOT / ".tools/review-2026-09-22-network.log"
if net.exists():
    text = net.read_text(encoding="utf-8-sig", errors="replace")
    data["network_log"] = text
    found = re.search(r"Evidence: (.+)", text)
    if found:
        summary = Path(found[1].strip()) / "summary.json"
        if summary.exists():
            data["network"] = json.loads(summary.read_text(encoding="utf-8-sig"))

data["map_sweep"] = []
for path in sorted((ROOT / ".tools").glob("review-2026-09-22-map-*.log")):
    if path.name.endswith(".godot.log"):
        continue
    data["map_sweep"].append({"log": str(path), **markers(path)})

unit_logs = sorted((ROOT / ".tools/verification-logs").glob("unit-tests-*.log"), key=lambda p: p.stat().st_mtime)
if unit_logs:
    text = unit_logs[-1].read_text(encoding="utf-8-sig", errors="replace")
    data["unit_tests"] = {"log": str(unit_logs[-1]), "summary": re.findall(r"TEST_SUMMARY[^\r\n]+", text)}

soak = ROOT / ".tools/review-2026-09-22-soak.log"
if soak.exists():
    data["soak_log"] = soak.read_text(encoding="utf-8-sig", errors="replace")
    found = re.search(r"Evidence: (.+)", data["soak_log"])
    if found:
        summary = Path(found[1].strip()) / "summary.json"
        if summary.exists():
            data["soak"] = json.loads(summary.read_text(encoding="utf-8-sig"))

(OUT / "results.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("Evidence retained:", OUT / "results.json")
print("Export discrepancies:", json.dumps(data["export_differences"], indent=2))
