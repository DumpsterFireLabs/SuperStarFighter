#!/usr/bin/env python3
"""Verify an exported client's embedded resources against a standalone server.

The editor runtime mounts the client's PCK to run a test driver, since shipping
templates do not execute external --script drivers. This checks actual packaged
client code/resources, not a native rendered client or signing/notarization.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def errors(text):
    return [line.strip() for line in text.splitlines()
            if line.lstrip().startswith(('ERROR:', 'SCRIPT ERROR:'))
            and line.strip() != 'ERROR: Failed to read the root certificate store.']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--server', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--port', type=int, default=18375)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535: parser.error('invalid port')
    for path in (args.godot, args.server, args.client):
        if not path.is_file(): parser.error(f'missing executable: {path}')
    output = ROOT / '.tools/package-interop' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    output.mkdir(parents=True)
    driver = output / 'package-client.gd'
    shutil.copyfile(ROOT / 'tools/package_interop_client.gd', driver)
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    failure = None
    client_exit = None
    native_exit = None
    try:
        with (output / 'native-client.log').open('w', encoding='utf-8') as native_log:
            native = subprocess.run([str(args.client.resolve()), '--headless', '--quit-after', '5',
                '--log-file', str(output / 'native-client.engine.log')], cwd=output,
                stdout=native_log, stderr=subprocess.STDOUT, timeout=30, creationflags=flags)
            native_exit = native.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        failure = str(error)
    with (output / 'server.log').open('w', encoding='utf-8') as server_log:
        server = subprocess.Popen([str(args.server.resolve()), '--headless', '--log-file', str(output / 'server.engine.log'),
            '--', '--password=review-package-smoke', f'--port={args.port}', '--test-fast-match', '--test-server-duration=25'],
            cwd=output, stdout=server_log, stderr=subprocess.STDOUT, creationflags=flags)
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                text = (output / 'server.log').read_text(encoding='utf-8', errors='replace')
                if 'SSF_MODE_READY=server' in text: break
                if server.poll() is not None: raise RuntimeError('server exited before readiness')
                time.sleep(0.05)
            else: raise RuntimeError('server did not become ready')
            with (output / 'client.log').open('w', encoding='utf-8') as client_log:
                result = subprocess.run([str(args.godot.resolve()), '--headless', '--path', str(output),
                    '--main-pack', str(args.client.resolve()), '--log-file', str(output / 'client.engine.log'),
                    '--script', str(driver), '--', f'--port={args.port}'], cwd=output,
                    stdout=client_log, stderr=subprocess.STDOUT, timeout=35, creationflags=flags)
                client_exit = result.returncode
            server.wait(timeout=30)
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
            failure = str(error)
        finally:
            if server.poll() is None:
                server.kill()
                server.wait()
    server_text = (output / 'server.log').read_text(encoding='utf-8', errors='replace')
    client_text = (output / 'client.log').read_text(encoding='utf-8', errors='replace') if (output / 'client.log').exists() else ''
    native_text = (output / 'native-client.log').read_text(encoding='utf-8', errors='replace')
    markers = [line.split('=', 1)[1] for line in client_text.splitlines() if line.startswith('SSF_PACKAGE_INTEROP=')]
    fixture = json.loads(markers[-1]) if markers else {}
    engine_errors = errors(server_text + '\n' + client_text + '\n' + native_text)
    passed = not failure and not engine_errors and native_exit == 0 and 'SSF_MODE_READY=client' in native_text and server.returncode == 0 and client_exit == 0 and fixture.get('ok', False) and 'SSF_SERVER_GRACEFUL_SHUTDOWN=test_duration' in server_text
    report = dict(passed=passed, fixture=fixture, failure=failure, errors=engine_errors,
        server_exit=server.returncode, client_exit=client_exit, native_client_startup_exit=native_exit,
        artifacts={name: dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                   for name, path in [('server', args.server), ('client', args.client)]},
        scope='Native headless client startup plus exported client PCK mounted in the pinned editor runtime, production client scene, standalone exported server; isolated runtime directory. No rendering or signing claim.')
    (output / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f"{'PASS' if passed else 'FAIL'} packaged interoperability: {json.dumps(fixture)}; evidence={output}")
    if not passed: raise SystemExit(1)


if __name__ == '__main__': main()
