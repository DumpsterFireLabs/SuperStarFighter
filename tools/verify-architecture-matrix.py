#!/usr/bin/env python3
"""Run fixed mixed-workload cases sequentially; never infer performance from FPS."""
import argparse, json, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    parser.add_argument('--strict-physics-budget', action='store_true')
    parser.add_argument('--profile', action='store_true', help='Include detailed projectile attribution; adds instrumentation overhead')
    args = parser.parse_args()
    output = ROOT / '.tools/architecture-matrix' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    output.mkdir(parents=True)
    results = []
    for case in range(5):
        command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--log-file', str(output / f'{case}.engine.log'), '--script', 'res://src/test/architecture_matrix_verifier.gd', '--', f'--case={case}']
        if args.strict_physics_budget: command.append('--strict-physics-budget')
        if args.profile: command.append('--profile')
        process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=180, cwd=ROOT)
        (output / f'{case}.log').write_text(process.stdout, encoding='utf-8')
        markers = [line.split('=', 1)[1] for line in process.stdout.splitlines() if line.startswith('SSF_ARCHITECTURE_MATRIX=')]
        unexpected = [line for line in process.stdout.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:')) and line != 'ERROR: Failed to read the root certificate store.']
        result = json.loads(markers[-1]) if markers else {'valid': False, 'case': case}
        phases = [line.split('=', 1)[1] for line in process.stdout.splitlines() if line.startswith('SSF_MATRIX_PHASES=')]
        result['attribution'] = json.loads(phases[-1]) if phases else {}
        result['valid'] = result['valid'] and process.returncode == 0 and not unexpected
        results.append(result)
        print(f"{'PASS' if result['valid'] else 'FAIL'} case {case}: {json.dumps(result)}", flush=True)
        (output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    print(f'Evidence: {output}', flush=True)
    if not all(row['valid'] for row in results): sys.exit(1)
if __name__ == '__main__': main()
