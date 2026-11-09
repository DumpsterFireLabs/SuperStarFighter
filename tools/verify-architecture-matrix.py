#!/usr/bin/env python3
"""Mixed-load correctness and opt-in named-hardware CPU regression acceptance."""
import argparse
import hashlib
import json
import math
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from ssf_tools import ROOT, default_godot, unexpected_errors
CASES_PATH = ROOT / 'tests/fixtures/architecture_matrix_cases.json'
WORKLOAD_VERSION = 2
TIMING_METRICS = ('p95_usec', 'p99_usec')


def workload_signature():
    paths = [CASES_PATH, *(ROOT / 'src/test' / name for name in (
        'architecture_matrix_verifier.gd', 'performance_benchmark.gd', 'combined_performance_benchmark.gd'))]
    # Normalize Git's platform line endings without hiding content changes.
    return hashlib.sha256('\n'.join(path.read_text(encoding='utf-8') for path in paths).encode()).hexdigest()


def marker(text, name):
    rows = [line.split('=', 1)[1] for line in text.splitlines() if line.startswith(name + '=')]
    if len(rows) != 1:
        raise ValueError(f'Expected one {name} marker, got {len(rows)}')
    return json.loads(rows[0])


def parse_result(text, exit_code, scenario):
    result = marker(text, 'SSF_ARCHITECTURE_MATRIX')
    result['attribution'] = marker(text, 'SSF_MATRIX_PHASES')
    result['host'] = marker(text, 'SSF_MATRIX_HOST')
    errors = unexpected_errors(text)
    # Independently reject empty, short, wrong-map or inactive-hazard fixtures.
    functional = result.get('functional_valid') is True and not errors
    functional &= result.get('map') == scenario['map'] and result.get('mode_id') == scenario['mode']
    functional &= result.get('humans') == 16 and result.get('npcs') == 16
    functional &= result.get('active_ticks') == 540 and result.get('timings', {}).get('samples') == 480
    functional &= result.get('minimum_alive_before_step') == 32 and result.get('minimum_projectiles_before_step') == 1024
    functional &= not scenario['field'] or result.get('field_activity_ticks', 0) > 0
    functional &= not scenario['solar'] or result.get('pulse_activity_ticks', 0) > 0
    for metric in (*TIMING_METRICS, 'max_usec', 'over_physics_budget'):
        value = result.get('timings', {}).get(metric)
        functional &= type(value) in (int, float) and math.isfinite(value) and value >= 0
    result['functional_valid'] = bool(functional)
    result['valid'] = bool(functional and result.get('valid') is True and exit_code == 0)
    return result


def make_baseline(results, hardware_label, cases, repeats):
    if not hardware_label.strip() or repeats < 3:
        raise ValueError('Performance evidence needs named hardware and at least three repetitions')
    if len(results) != len(cases) * repeats or not all(row['valid'] for row in results):
        raise ValueError('Cannot baseline incomplete or failing functional coverage')
    host = results[0]['host']
    if not host.get('cpu') or not host.get('engine') or any(row['host'] != host for row in results):
        raise ValueError('Hardware/engine identity must be present and stable')
    if any(row['attribution'].get('profiled') is not False for row in results):
        raise ValueError('Instrumented timings cannot be a performance baseline')
    timings = {}
    for case in cases:
        rows = [row for row in results if row['map'] == case['map'] and row['mode_id'] == case['mode']]
        if len(rows) != repeats:
            raise ValueError('Missing or duplicated case coverage')
        timings[case['map']] = {key: statistics.median(row['timings'][key] for row in rows) for key in TIMING_METRICS}
    return {'workload_version': WORKLOAD_VERSION, 'workload_signature': workload_signature(), 'hardware_label': hardware_label, 'host': host,
            'cases': cases, 'repeats': repeats, 'timings': timings}


def compare_baseline(current, reference):
    for key in ('workload_version', 'workload_signature', 'hardware_label', 'host', 'cases', 'repeats'):
        if current.get(key) != reference.get(key):
            raise ValueError(f'Incompatible performance baseline: {key}')
    failures = []
    for map_id, timings in current['timings'].items():
        for metric in TIMING_METRICS:
            previous = reference['timings'][map_id][metric]
            if type(previous) not in (int, float) or not math.isfinite(previous) or previous <= 0:
                raise ValueError('Baseline timings must be finite and positive')
            limit = max(previous * 1.15, previous + 250)
            if timings[metric] > limit:
                failures.append(f'{map_id} {metric}: {timings[metric]:.0f} > {limit:.0f} usec')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=default_godot())
    parser.add_argument('--strict-physics-budget', action='store_true')
    parser.add_argument('--profile', action='store_true', help='Diagnostic attribution with instrumentation overhead')
    parser.add_argument('--case', type=int, help='One diagnostic case; disallowed for baseline acceptance')
    parser.add_argument('--hardware-label', default='')
    lane = parser.add_mutually_exclusive_group()
    lane.add_argument('--record-baseline', type=Path, help='Create new evidence without overwriting an accepted baseline')
    lane.add_argument('--baseline', type=Path, help='Compare repeated unprofiled CPU work on matching hardware')
    args = parser.parse_args()
    performance = bool(args.record_baseline or args.baseline)
    if (performance or args.strict_physics_budget) and not args.hardware_label.strip():
        parser.error('Timing acceptance requires --hardware-label')
    if args.profile and (performance or args.strict_physics_budget):
        parser.error('Profile runs are diagnostic; timing acceptance must be unprofiled')
    if performance and args.case is not None:
        parser.error('Baseline acceptance requires the complete case matrix')
    if args.record_baseline and args.record_baseline.exists():
        parser.error('Baseline already exists; record a new candidate and review it explicitly')
    cases = json.loads(CASES_PATH.read_text(encoding='utf-8'))
    if args.case is not None and not 0 <= args.case < len(cases):
        parser.error('Case index is outside the manifest')
    selected = range(len(cases)) if args.case is None else [args.case]
    repeats = 3 if performance else 1
    output = ROOT / '.tools/architecture-matrix' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    output.mkdir(parents=True)
    metadata = {'hardware_label': args.hardware_label, 'workload_version': WORKLOAD_VERSION,
                'recorded_utc': datetime.now(timezone.utc).isoformat(),
                'manifest_sha256': hashlib.sha256(CASES_PATH.read_bytes()).hexdigest(),
                'profiled': args.profile, 'repeats': repeats, 'strict_physics_budget': args.strict_physics_budget,
                'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())}
    (output / 'run.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    results = []
    for repeat in range(repeats):
        for case in selected:
            name = f'{repeat}-{case}'
            command = [str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--log-file', str(output / f'{name}.engine.log'), '--script', 'res://src/test/architecture_matrix_verifier.gd', '--', f'--case={case}']
            if args.strict_physics_budget: command.append('--strict-physics-budget')
            if args.profile: command.append('--profile')
            try:
                process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=180, cwd=ROOT)
                (output / f'{name}.log').write_text(process.stdout, encoding='utf-8')
                result = parse_result(process.stdout, process.returncode, cases[case])
            except (ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
                result = {'valid': False, 'functional_valid': False, 'case': case, 'error': str(error)}
            results.append(result)
            print(f"{'PASS' if result['valid'] else 'FAIL'} {name} {cases[case]['map']}: {json.dumps(result.get('timings', result))}", flush=True)
            (output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    valid = all(row['valid'] for row in results)
    if performance and valid:
        current = make_baseline(results, args.hardware_label, cases, repeats)
        current['evidence'] = metadata
        if args.record_baseline:
            args.record_baseline.parent.mkdir(parents=True, exist_ok=True)
            with args.record_baseline.open('x', encoding='utf-8') as stream:
                stream.write(json.dumps(current, indent=2) + '\n')
        else:
            try:
                failures = compare_baseline(current, json.loads(args.baseline.read_text(encoding='utf-8')))
            except (ValueError, KeyError, TypeError, OSError) as error:
                failures = [str(error)]
            valid = not failures
            print('CPU_BASELINE ' + ('FAIL: ' + '; '.join(failures) if failures else 'PASS'), flush=True)
            (output / 'comparison.json').write_text(json.dumps({'functional_valid': True, 'timing_valid': valid, 'valid': valid, 'failures': failures, 'current': current}, indent=2) + '\n', encoding='utf-8')
    print(f'Evidence: {output}', flush=True)
    return 0 if valid else 1


if __name__ == '__main__':
    sys.exit(main())
