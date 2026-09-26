#!/usr/bin/env python3
"""Exercise the real TCP game transport through a deterministic loopback fault proxy."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from datetime import datetime, timezone
from uuid import uuid4

from tcp_link_proxy import StreamLink, StreamProxy

ROOT = Path(__file__).resolve().parents[1]
BLACKOUT_WINDOW = (4.0, 4.7)
PROFILES = {
    "baseline": {},
    "latency": {"delay": 0.100, "jitter": 0.035},
    # TCP recovers loss by retransmission: modelled as head-of-line stalls.
    "loss": {"loss": 0.12},
    "blackout": {"blackout": True},
    "combined": {"delay": 0.060, "jitter": 0.025, "loss": 0.08, "blackout": True},
    "tail_loss": {"settlement_blackout": 0.35},
    "limited_bandwidth": {"delay": 0.05, "jitter": 0.02, "bytes_per_second": 4096},
}


def run_profile(godot, name, port, seed, output, shield_only=False):
    profile = PROFILES[name]
    link = StreamLink(profile, seed)
    proxy = StreamProxy(port + 1, port, link, max_connections=1)
    log_path = output / f"{name}.log"
    try:
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen([
                str(godot), "--headless", "--path", str(ROOT), "--log-file",
                str(output / f"{name}.godot.log"), "--script",
                "res://src/test/network_impairment_verifier.gd", "--",
                f"--server-port={port}", f"--proxy-port={port + 1}",
            ] + (["--shield-only"] if shield_only else []), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            started = time.monotonic()
            settlement_started = None
            try:
                while process.poll() is None:
                    now = time.monotonic()
                    if now - started > 60:
                        raise RuntimeError(f"{name}: fixture timed out")
                    if profile.get("settlement_blackout") and settlement_started is None:
                        if "IMPAIRMENT_SETTLEMENT_BEGIN" in log_path.read_text(encoding="utf-8", errors="replace"):
                            settlement_started = now
                    hold = {}
                    elapsed = now - started
                    # Faults include handshake/control traffic. The blackout is
                    # bounded; held fire must stop through server input expiry.
                    if profile.get("blackout") and BLACKOUT_WINDOW[0] <= elapsed < BLACKOUT_WINDOW[1]:
                        hold = {"up": started + BLACKOUT_WINDOW[1], "down": started + BLACKOUT_WINDOW[1]}
                    if settlement_started is not None and now - settlement_started < profile["settlement_blackout"]:
                        hold["up"] = settlement_started + profile["settlement_blackout"]
                    proxy.poll(now, 0.002, hold_until=hold)
                    if len(link.queue) > 16384:
                        raise RuntimeError("Proxy queue exceeded its bounded fixture budget")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
    finally:
        proxy.close()
    counters = link.counters
    text = log_path.read_text(encoding="utf-8")
    # Preserve fault counts even when engine assertions or coverage fail.
    (output / f"{name}.proxy.json").write_text(json.dumps(dict(
        profile=name, seed=seed, configuration=profile, stream=counters,
        peak_queued_segments=link.peak, exit_code=process.returncode), indent=2) + "\n", encoding="utf-8")
    if process.returncode or "SSF_IMPAIRMENT_OK=" not in text or "SCRIPT ERROR:" in text:
        raise RuntimeError(f"{name}: Godot verification failed; see {log_path}")
    errors = [line for line in text.splitlines() if line.startswith("ERROR:") and line != "ERROR: Failed to read the root certificate store."]
    if errors:
        raise RuntimeError(f"{name}: unexpected errors: {errors}")
    for direction, row in counters.items():
        required = ["received", "delivered"]
        if profile.get("loss"):
            required.append("loss_stalls")
        if profile.get("blackout"):
            required.append("held")
        if profile.get("delay"):
            required.append("delayed")
        if any(row[key] == 0 for key in required):
            raise RuntimeError(f"{name}: requested fault was not observed in {direction}: {row}")
        if profile.get("bytes_per_second") and row["bandwidth_wait_seconds"] <= 0:
            raise RuntimeError(f"{name}: bandwidth serialization was not exercised in {direction}")
    fixture = json.loads(next(line.split("=", 1)[1] for line in text.splitlines() if line.startswith("SSF_IMPAIRMENT_OK=")))
    if profile.get("settlement_blackout") and (counters["up"]["held"] == 0 or fixture["delivery"]["neutral_send_attempts"] < 2):
        raise RuntimeError(f"{name}: did not exercise a stall and retry of the final neutral barrier")
    result = dict(profile=name, seed=seed, shield_only=shield_only, configuration=profile, stream=counters,
                  peak_queued_segments=link.peak, elapsed_seconds=time.monotonic() - started, fixture=fixture)
    (output / f"{name}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"PASS {name}: {fixture['snapshots']} snapshots, resources converged, faults={counters}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / ".tools/godot/Godot_v4.7.2-stable_win64_console.exe")
    parser.add_argument("--profile", choices=["all", *PROFILES], default="all")
    parser.add_argument("--port", type=int, default=17780)
    parser.add_argument("--seed", type=int, default=230926)
    parser.add_argument("--seeds", type=int, default=1, help="consecutive seeds to run; failed runs are retained and reported")
    parser.add_argument("--shield-only", action="store_true", help="isolate shield tap/volley timing and convergence from ability-delivery coverage")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534:
        parser.error("port must leave room for the adjacent proxy port")
    if not 1 <= args.seeds <= 20:
        parser.error("seeds must be between 1 and 20")
    output = ROOT / ".tools/network-impairment" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid4().hex[:8])
    output.mkdir(parents=True, exist_ok=True)
    print(f"Evidence: {output}", flush=True)
    names = list(PROFILES) if args.profile == "all" else [args.profile]
    results = []
    failures = 0
    for seed in range(args.seed, args.seed + args.seeds):
        seed_output = output / f"seed-{seed}"
        seed_output.mkdir()
        for name in names:
            try:
                result = run_profile(args.godot.resolve(), name, args.port, seed, seed_output, args.shield_only)
                result["passed"] = True
            except (RuntimeError, OSError) as error:
                failures += 1
                result = dict(profile=name, seed=seed, shield_only=args.shield_only, passed=False, error=str(error))
                print(f"FAIL {name} seed={seed}: {error}", flush=True)
            results.append(result)
            (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(f"Impairment verification: {len(results) - failures}/{len(results)} passed; evidence={output}", flush=True)
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
