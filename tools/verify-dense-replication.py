#!/usr/bin/env python3
"""Measure actual UDP payload bytes for 32 production ENet clients on loopback.
Includes admission, RPC framing, ENet control and retransmissions; excludes IP/UDP
headers. CPU scheduling here is not a WAN capacity or FPS certification.
"""
import argparse, json, select, socket, subprocess, time
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--port', type=int, default=17880)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534: parser.error('invalid port')
    output = ROOT / '.tools/dense-replication' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    output.mkdir(parents=True)
    counts = {'up': 0, 'down': 0}
    packets = {'up': 0, 'down': 0}
    windows = {}
    connections = {}
    reverse = {}
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, (output / 'fixture.log').open('w', encoding='utf-8') as log:
        front.bind(('127.0.0.1', args.port + 1))
        front.setblocking(False)
        process = subprocess.Popen([str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--log-file', str(output / 'engine.log'), '--script', 'res://src/test/dense_replication_verifier.gd', '--', f'--port={args.port}'], stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        try:
            while process.poll() is None:
                if time.monotonic() - started > 35: raise RuntimeError('dense fixture timeout')
                readable, _, _ = select.select([front, *reverse], [], [], 0.002)
                for source in readable:
                    try: data, address = source.recvfrom(65535)
                    except (BlockingIOError, ConnectionResetError): continue
                    direction = 'up' if source is front else 'down'
                    counts[direction] += len(data)
                    packets[direction] += 1
                    if direction == 'up':
                        if address not in connections:
                            back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                            back.bind(('127.0.0.1', 0))
                            back.connect(('127.0.0.1', args.port))
                            back.setblocking(False)
                            connections[address] = back
                            reverse[back] = address
                        connections[address].send(data)
                    else:
                        front.sendto(data, reverse[source])
                        window = int((time.monotonic() - started) * 60)
                        windows[window] = windows.get(window, 0) + len(data)
        finally:
            if process.poll() is None: process.kill(); process.wait()
            for back in reverse: back.close()
    text = (output / 'fixture.log').read_text(encoding='utf-8')
    markers = [line.split('=', 1)[1] for line in text.splitlines() if line.startswith('SSF_DENSE_RESULT=')]
    if process.returncode or not markers or 'SCRIPT ERROR:' in text: raise RuntimeError(f'dense fixture failed: {output}')
    fixture = json.loads(markers[-1])
    result = {'udp_payload_bytes': counts, 'datagrams': packets, 'peak_downstream_bytes_per_16_7ms_window': max(windows.values(), default=0), 'elapsed_seconds': time.monotonic() - started, 'fixture': fixture}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    if not fixture['passed'] or len(connections) != 32: raise RuntimeError(f'incomplete fan-out: {output}')
    print(f'PASS dense replication: {json.dumps(result)}; evidence={output}')

if __name__ == '__main__': main()
