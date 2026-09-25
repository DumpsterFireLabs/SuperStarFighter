#!/usr/bin/env python3
"""Verify wss:// through a loopback TLS-terminating reverse proxy.

Stands in for Cloudflare: the client speaks real TLS to the proxy, which
forwards plain WebSocket bytes to a --behind-proxy server bound to 127.0.0.1.
Binds only loopback and changes no host networking or certificate stores.
"""
import argparse
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def pump(source, destination):
    try:
        while data := source.recv(65536):
            destination.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (source, destination):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def serve(listener, context, server_port, stop):
    listener.settimeout(0.2)
    while not stop.is_set():
        try:
            raw, _ = listener.accept()
        except socket.timeout:
            continue
        try:
            client = context.wrap_socket(raw, server_side=True)
            upstream = socket.create_connection(('127.0.0.1', server_port), timeout=5)
        except (OSError, ssl.SSLError) as error:
            print(f'proxy connection failed: {error}', flush=True)
            raw.close()
            continue
        upstream.settimeout(None)
        client.settimeout(None)
        threading.Thread(target=pump, args=(client, upstream), daemon=True).start()
        threading.Thread(target=pump, args=(upstream, client), daemon=True).start()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--port', type=int, default=17990)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65534: parser.error('port must leave room for the adjacent proxy port')
    with tempfile.TemporaryDirectory() as directory:
        cert_dir = Path(directory)
        log_path = cert_dir / 'fixture.log'
        stop = threading.Event()
        with log_path.open('w', encoding='utf-8') as log:
            process = subprocess.Popen([str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--script',
                                        'res://src/test/wss_proxy_verifier.gd', '--', f'--server-port={args.port}',
                                        f'--proxy-port={args.port + 1}', f'--cert-dir={cert_dir}'],
                                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            listeners = []
            try:
                deadline = time.monotonic() + 30
                while not (cert_dir / 'cert.pem').exists() or not (cert_dir / 'key.pem').exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError('fixture certificate was not written')
                    time.sleep(0.05)
                time.sleep(0.2)
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(cert_dir / 'cert.pem', cert_dir / 'key.pem')
                # "localhost" may resolve to either loopback family.
                for family, address in ((socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')):
                    listener = socket.socket(family, socket.SOCK_STREAM)
                    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    try:
                        listener.bind((address, args.port + 1))
                    except OSError:
                        listener.close()
                        continue
                    listener.listen(16)
                    listeners.append(listener)
                    threading.Thread(target=serve, args=(listener, context, args.port, stop), daemon=True).start()
                if not listeners:
                    raise RuntimeError('could not bind a loopback proxy listener')
                (cert_dir / 'proxy.ready').write_text('ready\n', encoding='utf-8')
                process.wait(timeout=60)
            finally:
                stop.set()
                for listener in listeners:
                    listener.close()
                if process.poll() is None:
                    process.kill()
                    process.wait()
        text = log_path.read_text(encoding='utf-8', errors='replace')
    errors = [line.strip() for line in text.splitlines() if line.lstrip().startswith(('ERROR:', 'SCRIPT ERROR:'))
              and line.strip() != 'ERROR: Failed to read the root certificate store.']
    marker = next((line for line in text.splitlines() if line.startswith('SSF_WSS_OK=')), '')
    passed = process.returncode == 0 and '"ok":true' in marker and not errors
    print(marker or text[-2000:])
    if errors: print('Unexpected engine errors:', errors)
    print(f"{'PASS' if passed else 'FAIL'} wss proxy verification")
    if not passed: raise SystemExit(1)


if __name__ == '__main__': main()
