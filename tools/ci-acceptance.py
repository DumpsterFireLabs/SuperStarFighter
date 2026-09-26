#!/usr/bin/env python3
"""Portable CI acceptance using the repository's pinned Godot version.
Functional checks run on shared runners; timing budgets require named hardware.
"""
import argparse, hashlib, json, os, platform, re, subprocess, sys, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '4.7.2-stable'
OUTPUT = ROOT / '.tools/ci-acceptance'


def bootstrap():
    system = platform.system()
    suffix, executable = {
        'Windows': ('win64.exe.zip', f'Godot_v{VERSION}_win64_console.exe'),
        'Linux': ('linux.x86_64.zip', f'Godot_v{VERSION}_linux.x86_64'),
        'Darwin': ('macos.universal.zip', 'Godot.app/Contents/MacOS/Godot'),
    }[system]
    folder = ROOT / '.tools/ci-godot'
    folder.mkdir(parents=True, exist_ok=True)
    name = f'Godot_v{VERSION}_{suffix}'
    base = f'https://github.com/godotengine/godot/releases/download/{VERSION}/'
    checksum = urllib.request.urlopen(base + 'SHA512-SUMS.txt', timeout=60).read().decode()
    rows = [line.split() for line in checksum.splitlines() if line.split() and line.split()[-1].lstrip('*').endswith(name)]
    if len(rows) != 1: raise RuntimeError(f'No unique official checksum for {name}')
    archive = folder / name
    urllib.request.urlretrieve(base + name, archive)
    if hashlib.sha512(archive.read_bytes()).hexdigest() != rows[0][0].lower(): raise RuntimeError('Godot checksum mismatch')
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            if not (folder / member.filename).resolve().is_relative_to(folder.resolve()): raise RuntimeError('Unsafe archive path')
        bundle.extractall(folder)
    path = folder / executable
    path.chmod(path.stat().st_mode | 0o111)
    return path


def validate(text, exit_code, marker, expected_exit=0):
    errors = [line.strip() for line in text.splitlines() if line.lstrip().startswith(('ERROR:', 'SCRIPT ERROR:')) and line.strip() != 'ERROR: Failed to read the root certificate store.']
    if exit_code != expected_exit or not re.search(marker, text) or errors:
        raise RuntimeError(f'Acceptance failed: exit={exit_code}, marker={marker}, errors={errors[:5]}')


def run_engine(godot, name, args, marker, timeout=300, expected_exit=0):
    command = [str(godot), '--headless', '--path', str(ROOT), '--log-file', str(OUTPUT / f'{name}.engine.log'), *args]
    with (OUTPUT / f'{name}.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, timeout=timeout)
    text = (OUTPUT / f'{name}.log').read_text(encoding='utf-8', errors='replace')
    validate(text, result.returncode, marker, expected_exit)
    print(f'PASS {name}', flush=True)
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, help='Use an already verified local engine; otherwise download and check official SHA-512')
    parser.add_argument('--memory-cycles', type=int, default=80)
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    godot = args.godot.resolve() if args.godot else bootstrap()
    for command in [['tools/update-release-metadata.py'], ['tools/update-export-policy.py', '--check'], ['-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_*.py']]:
        subprocess.run([sys.executable, *command], cwd=ROOT, check=True, timeout=120)
    run_engine(godot, 'import', ['--editor', '--quit'], r'Godot Engine')
    run_engine(godot, 'startup', ['--quit-after', '5'], 'SSF_MODE_READY=client')
    run_engine(godot, 'unit', ['--', '--run-tests'], r'TEST_SUMMARY passed=\d+ failed=0\b')
    # Both a real forced assertion and a zero-exit engine error must be rejected.
    run_engine(godot, 'forced-failure', ['--', '--run-tests', '--force-test-failure'], r'TEST_SUMMARY passed=\d+ failed=1\b', expected_exit=1)
    negative = OUTPUT / 'negative.gd'
    negative.write_text('extends SceneTree\nfunc _initialize():\n\tpush_error("SSF_GATE_NEGATIVE")\n\tprint("PASS_MARKER")\n\tquit(0)\n', encoding='utf-8')
    try:
        run_engine(godot, 'zero-exit-error', ['--script', str(negative)], 'PASS_MARKER')
    except RuntimeError as error:
        if 'SSF_GATE_NEGATIVE' not in str(error): raise
        print('PASS zero-exit errors are rejected', flush=True)
    else: raise RuntimeError('Gate accepted a real engine error')
    for script in ['verify-dense-replication.py', 'verify-architecture-matrix.py']:
        subprocess.run([sys.executable, str(ROOT / 'tools' / script), '--godot', str(godot)], cwd=ROOT, check=True, timeout=1000)
    run_engine(godot, 'reconnect', ['--script', 'res://src/test/reconnect_verifier.gd'], r'SSF_RECONNECT_OK\b')
    run_engine(godot, 'memory', ['--script', 'res://src/test/architecture_memory_verifier.gd', '--', f'--cycles={args.memory_cycles}'], r'SSF_ARCHITECTURE_MEMORY=.*"valid":true', timeout=1200)
    print('CI_ACCEPTANCE_PASSED', flush=True)

if __name__ == '__main__': main()
