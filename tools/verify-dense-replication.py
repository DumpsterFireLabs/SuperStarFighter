#!/usr/bin/env python3
"""Measure actual TCP stream bytes for 32 production clients on loopback.
Includes admission, RPC and WebSocket framing; excludes IP/TCP headers and
kernel retransmission. CPU scheduling here is not a WAN capacity or FPS
certification.
"""
import argparse, json, subprocess, time
from pathlib import Path
from datetime import datetime, timezone

from tcp_link_proxy import StreamLink, StreamProxy

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    'baseline': {},
    'loss_jitter': {'delay': 0.050, 'jitter': 0.020, 'loss': 0.05},
    # Limited links pause reads once queue_seconds of bytes are waiting, so the
    # server sees TCP backpressure instead of tail drops.
    'congested': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 98304, 'queue_seconds': 0.200},
    'shallow_queue': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 98304, 'queue_seconds': 0.100},
    'undersupplied': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 65536, 'queue_seconds': 0.200},
}


def run_profile(godot, name, port, seed, output, exercise_recovery):
    output.mkdir(parents=True)
    link = StreamLink(PROFILES[name], seed)
    proxy = StreamProxy(port + 1, port, link, max_connections=32)
    windows = {}
    started = time.monotonic()
    def count_window(size):
        window = int((time.monotonic() - started) * 60)
        windows[window] = windows.get(window, 0) + size
    proxy.downstream_listeners.append(count_window)
    settlement, next_log_check, failure = False, 0.0, None
    log_path = output / 'fixture.log'
    with log_path.open('w', encoding='utf-8') as log:
        command = [str(godot), '--headless', '--path', str(ROOT), '--log-file', str(output / 'engine.log'),
                   '--script', 'res://src/test/dense_replication_verifier.gd', '--', f'--port={port}']
        if exercise_recovery: command.append('--exercise-recovery')
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            while process.poll() is None:
                now = time.monotonic()
                if now - started > 75: raise RuntimeError('dense fixture timeout')
                if now >= next_log_check:
                    settlement = 'DENSE_SETTLEMENT_BEGIN' in log_path.read_text(encoding='utf-8', errors='replace')
                    next_log_check = now + 0.100
                proxy.poll(time.monotonic(), 0.001, impaired=not settlement)
                if len(link.queue) > 65536: raise RuntimeError('Proxy exceeded its bounded segment budget')
        except (RuntimeError, OSError) as error: failure = str(error)
        finally:
            if process.poll() is None: process.kill(); process.wait()
            proxy.close()
    text = log_path.read_text(encoding='utf-8')
    markers = [line.split('=', 1)[1] for line in text.splitlines() if line.startswith('SSF_DENSE_RESULT=')]
    fixture = json.loads(markers[-1]) if markers else {}
    errors = [line.strip() for line in text.splitlines() if line.lstrip().startswith(('ERROR:', 'SCRIPT ERROR:'))
              and line.strip() != 'ERROR: Failed to read the root certificate store.']
    covered = True
    if name == 'loss_jitter': covered = all(r['loss_stalls'] > 0 and r['delayed'] > 0 for r in link.counters.values())
    if name in ('congested', 'shallow_queue', 'undersupplied'): covered = link.counters['down']['max_queue_wait_seconds'] > 0
    passed = not failure and not errors and process.returncode == 0 and fixture.get('passed', False) and proxy.peak_connections == 32 and covered
    result = dict(passed=passed, profile=name, seed=seed, configuration=PROFILES[name],
        elapsed_seconds=time.monotonic() - started, exit_code=process.returncode, errors=errors,
        failure=failure, connections=dict(relayed=proxy.accepted, refused=proxy.refused, peak=proxy.peak_connections), stream=link.counters, peak_queued_segments=link.peak,
        pending_at_exit=len(link.queue), healthy_settlement_observed=settlement,
        peak_downstream_bytes_per_16_7ms_window=max(windows.values(), default=0), fixture=fixture,
        scope='TCP stream bytes include admission and WebSocket framing; application bytes cover replication only. Per-client links; final six seconds healthy in extended profiles. Static dense world, not WAN capacity or combat fairness certification.')
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"{'PASS' if passed else 'FAIL'} dense {name}: clients={proxy.peak_connections} refused={proxy.refused} faults={link.counters}; evidence={output}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--port', type=int, default=17880)
    parser.add_argument('--profile', choices=['all', *PROFILES], default='baseline')
    parser.add_argument('--seed', type=int, default=230926)
    parser.add_argument('--exercise-recovery', action='store_true')
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534: parser.error('invalid port')
    output = ROOT / '.tools/dense-replication' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    names = list(PROFILES) if args.profile == 'all' else [args.profile]
    results = [run_profile(args.godot.resolve(), name, args.port, args.seed, output / name,
                          args.exercise_recovery or args.profile != 'baseline') for name in names]
    (output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    if not all(row['passed'] for row in results): raise SystemExit(1)


if __name__ == '__main__': main()
