#!/usr/bin/env python3
"""Exercise real ENet datagrams through a deterministic loopback fault proxy."""
import argparse
import heapq
import json
from pathlib import Path
import random
import select
import socket
import subprocess
import time
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    "baseline": {},
    "latency": {"delay": 0.100, "jitter": 0.035},
    "loss": {"loss": 0.12},
    "reorder": {"reorder": 0.30, "duplicate": 0.10},
    "blackout": {"blackout": True},
    "combined": {"delay": 0.060, "jitter": 0.025, "loss": 0.08,
                 "reorder": 0.20, "duplicate": 0.05, "blackout": True},
    "tail_loss": {"settlement_blackout": 0.35},
}


def run_profile(godot, name, port, seed, output, shield_only=False):
    profile = PROFILES[name]
    rng = random.Random(seed)
    counters = {direction: dict(received=0, delivered=0, dropped=0, duplicated=0,
                               reordered=0, delayed=0, settlement_dropped=0) for direction in ("up", "down")}
    queue, serial, high_water, peak_queue = [], 0, {"up": 0, "down": 0}, 0
    client_address = None
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, \
            socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as back:
        # Never bind an externally reachable interface or modify host networking.
        front.bind(("127.0.0.1", port + 1))
        back.bind(("127.0.0.1", 0))
        back.connect(("127.0.0.1", port))
        front.setblocking(False)
        back.setblocking(False)
        log_path = output / f"{name}.log"
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
                    readable, _, _ = select.select([front, back], [], [], 0.002)
                    for source in readable:
                        try:
                            packet, address = source.recvfrom(65535)
                        except (BlockingIOError, ConnectionResetError):
                            continue
                        direction = "up" if source is front else "down"
                        if source is front:
                            if client_address is None:
                                client_address = address
                            if address != client_address:
                                continue
                        elif client_address is None:
                            continue
                        row = counters[direction]
                        row["received"] += 1
                        elapsed = now - started
                        if (direction == "up" and settlement_started is not None
                                and now - settlement_started < profile["settlement_blackout"]):
                            row["dropped"] += 1
                            row["settlement_dropped"] += 1
                            continue
                        # Faults include handshake/control traffic. The blackout is
                        # bounded; held fire must stop through server input expiry.
                        if (profile.get("blackout") and 4.0 <= elapsed < 4.7) or rng.random() < profile.get("loss", 0):
                            row["dropped"] += 1
                            continue
                        delay = max(0, profile.get("delay", 0) + rng.uniform(-1, 1) * profile.get("jitter", 0))
                        if rng.random() < profile.get("reorder", 0):
                            delay += 0.140
                        if delay:
                            row["delayed"] += 1
                        serial += 1
                        heapq.heappush(queue, (now + delay, serial, direction, packet))
                        # A short focused fixture must actually exercise every
                        # requested fault, not randomly miss duplication entirely.
                        if rng.random() < profile.get("duplicate", 0) or (profile.get("duplicate") and row["duplicated"] == 0 and row["received"] >= 8):
                            row["duplicated"] += 1
                            heapq.heappush(queue, (now + delay + 0.010, serial, direction, packet))
                        peak_queue = max(peak_queue, len(queue))
                    while queue and queue[0][0] <= time.monotonic():
                        _, sequence, direction, packet = heapq.heappop(queue)
                        if sequence < high_water[direction]:
                            counters[direction]["reordered"] += 1
                        high_water[direction] = max(high_water[direction], sequence)
                        if direction == "up":
                            back.send(packet)
                        else:
                            front.sendto(packet, client_address)
                        counters[direction]["delivered"] += 1
                    if len(queue) > 4096:
                        raise RuntimeError("Proxy queue exceeded its bounded fixture budget")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
        text = log_path.read_text(encoding="utf-8")
        # Preserve fault counts even when engine assertions or coverage fail.
        (output / f"{name}.proxy.json").write_text(json.dumps(dict(
            profile=name, seed=seed, configuration=profile, datagrams=counters,
            peak_queued_datagrams=peak_queue, exit_code=process.returncode), indent=2) + "\n", encoding="utf-8")
        if process.returncode or "SSF_IMPAIRMENT_OK=" not in text or "SCRIPT ERROR:" in text:
            raise RuntimeError(f"{name}: Godot verification failed; see {log_path}")
        errors = [line for line in text.splitlines() if line.startswith("ERROR:") and line != "ERROR: Failed to read the root certificate store."]
        if errors:
            raise RuntimeError(f"{name}: unexpected errors: {errors}")
        for direction, row in counters.items():
            required = ["received", "delivered"]
            if profile.get("loss") or profile.get("blackout"):
                required.append("dropped")
            if profile.get("duplicate"):
                required.append("duplicated")
            if profile.get("reorder"):
                required.append("reordered")
            if profile.get("delay"):
                required.append("delayed")
            if any(row[key] == 0 for key in required):
                raise RuntimeError(f"{name}: requested fault was not observed in {direction}: {row}")
        fixture = json.loads(next(line.split("=", 1)[1] for line in text.splitlines() if line.startswith("SSF_IMPAIRMENT_OK=")))
        if profile.get("settlement_blackout") and (counters["up"]["settlement_dropped"] == 0 or fixture["delivery"]["neutral_send_attempts"] < 2):
            raise RuntimeError(f"{name}: did not exercise loss and retry of the final neutral barrier")
        result = dict(profile=name, seed=seed, shield_only=shield_only, configuration=profile, datagrams=counters,
                      peak_queued_datagrams=peak_queue, fixture=fixture)
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
