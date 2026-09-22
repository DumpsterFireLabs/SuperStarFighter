#!/usr/bin/env python3
"""Measure actual UDP payload bytes for 32 production ENet clients on loopback.
Includes admission, RPC framing, ENet control and retransmissions; excludes IP/UDP
headers. CPU scheduling here is not a WAN capacity or FPS certification.
"""
import argparse, heapq, json, random, select, socket, subprocess, time
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {
    'baseline': {},
    'loss_jitter': {'delay': 0.050, 'jitter': 0.020, 'loss': 0.05},
    'congested': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 98304, 'queue_seconds': 0.200},
    'shallow_queue': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 98304, 'queue_seconds': 0.100},
    'undersupplied': {'delay': 0.050, 'jitter': 0.020, 'bytes_per_second': 65536, 'queue_seconds': 0.200},
}


class LinkQueue:
    """Bounded independent bandwidth reservations for each client/direction."""
    def __init__(self, profile, seed):
        self.profile, self.rng = profile, random.Random(seed)
        self.available, self.queue = {}, []
        self.serial = self.peak = 0
        self.counters = {d: dict(received=0, received_bytes=0, delivered=0,
            delivered_bytes=0, loss_drops=0, congestion_drops=0, delayed=0,
            max_queue_wait_seconds=0.0) for d in ('up', 'down')}

    def receive(self, now, key, packet, destination, impaired=True):
        direction, _ = key
        row = self.counters[direction]
        row['received'] += 1
        row['received_bytes'] += len(packet)
        profile = self.profile if impaired else {}
        if self.rng.random() < profile.get('loss', 0):
            row['loss_drops'] += 1
            return
        # Honor already reserved packets when the healthy settlement begins.
        finish = max(now, self.available.get(key, now))
        if profile.get('bytes_per_second'):
            finish += len(packet) / profile['bytes_per_second']
            if finish - now > profile['queue_seconds']:
                row['congestion_drops'] += 1
                return
        self.available[key] = finish
        wait = finish - now
        row['max_queue_wait_seconds'] = max(row['max_queue_wait_seconds'], wait)
        delay = max(0, profile.get('delay', 0) + self.rng.uniform(-1, 1) * profile.get('jitter', 0))
        if delay + wait > 0: row['delayed'] += 1
        self.serial += 1
        heapq.heappush(self.queue, (finish + delay, self.serial, direction, packet, destination))
        self.peak = max(self.peak, len(self.queue))
        if len(self.queue) > 32768: raise RuntimeError('Proxy exceeded its bounded datagram budget')

    def deliver(self, now, sender):
        while self.queue and self.queue[0][0] <= now:
            _, _, direction, packet, destination = heapq.heappop(self.queue)
            sender(direction, packet, destination)
            self.counters[direction]['delivered'] += 1
            self.counters[direction]['delivered_bytes'] += len(packet)


def run_profile(godot, name, port, seed, output, exercise_recovery):
    output.mkdir(parents=True)
    proxy = LinkQueue(PROFILES[name], seed)
    connections, reverse, windows = {}, {}, {}
    started = time.monotonic()
    settlement, next_log_check, failure = False, 0.0, None
    log_path = output / 'fixture.log'
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, log_path.open('w', encoding='utf-8') as log:
        front.bind(('127.0.0.1', port + 1))
        front.setblocking(False)
        command = [str(godot), '--headless', '--path', str(ROOT), '--log-file', str(output / 'engine.log'),
                   '--script', 'res://src/test/dense_replication_verifier.gd', '--', f'--port={port}']
        if exercise_recovery: command.append('--exercise-recovery')
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        def send(direction, packet, destination):
            if direction == 'up': destination.send(packet)
            else:
                front.sendto(packet, destination)
                window = int((time.monotonic() - started) * 60)
                windows[window] = windows.get(window, 0) + len(packet)
        try:
            while process.poll() is None:
                now = time.monotonic()
                if now - started > 75: raise RuntimeError('dense fixture timeout')
                if now >= next_log_check:
                    settlement = 'DENSE_SETTLEMENT_BEGIN' in log_path.read_text(encoding='utf-8', errors='replace')
                    next_log_check = now + 0.100
                readable, _, _ = select.select([front, *reverse], [], [], 0.001)
                for source in readable:
                    # Bounded draining prevents a busy peer from starving timers.
                    for _ in range(64):
                        try: packet, address = source.recvfrom(65535)
                        except (BlockingIOError, ConnectionResetError): break
                        if source is front:
                            if address not in connections:
                                if len(connections) >= 32: raise RuntimeError('unexpected extra client')
                                back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                                back.bind(('127.0.0.1', 0))
                                back.connect(('127.0.0.1', port))
                                back.setblocking(False)
                                connections[address], reverse[back] = back, address
                            proxy.receive(time.monotonic(), ('up', address), packet, connections[address], not settlement)
                        else:
                            proxy.receive(time.monotonic(), ('down', reverse[source]), packet, reverse[source], not settlement)
                proxy.deliver(time.monotonic(), send)
        except (RuntimeError, OSError) as error: failure = str(error)
        finally:
            if process.poll() is None: process.kill(); process.wait()
            for back in reverse: back.close()
    text = log_path.read_text(encoding='utf-8')
    markers = [line.split('=', 1)[1] for line in text.splitlines() if line.startswith('SSF_DENSE_RESULT=')]
    fixture = json.loads(markers[-1]) if markers else {}
    errors = [line.strip() for line in text.splitlines() if line.lstrip().startswith(('ERROR:', 'SCRIPT ERROR:'))
              and line.strip() != 'ERROR: Failed to read the root certificate store.']
    covered = True
    if name == 'loss_jitter': covered = all(r['loss_drops'] > 0 and r['delayed'] > 0 for r in proxy.counters.values())
    if name in ('congested', 'shallow_queue', 'undersupplied'): covered = proxy.counters['down']['max_queue_wait_seconds'] > 0
    passed = not failure and not errors and process.returncode == 0 and fixture.get('passed', False) and len(connections) == 32 and covered
    result = dict(passed=passed, profile=name, seed=seed, configuration=PROFILES[name],
        elapsed_seconds=time.monotonic() - started, exit_code=process.returncode, errors=errors,
        failure=failure, datagrams=proxy.counters, peak_queued_datagrams=proxy.peak,
        pending_at_exit=len(proxy.queue), healthy_settlement_observed=settlement,
        peak_downstream_bytes_per_16_7ms_window=max(windows.values(), default=0), fixture=fixture,
        scope='UDP payload includes admission and retransmission; application bytes cover replication only. Per-client links; final six seconds healthy in extended profiles. Static dense world, not WAN capacity or combat fairness certification.')
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"{'PASS' if passed else 'FAIL'} dense {name}: clients={len(connections)} faults={proxy.counters}; evidence={output}", flush=True)
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
