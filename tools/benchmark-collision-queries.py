#!/usr/bin/env python3
"""Alternate fixed collision queries against an explicit local Git baseline.

Measures query CPU work, not full simulation or frame throughput. The ship-query
control is unchanged by the obstacle occupancy optimization. Full combat parity
belongs to the existing exhaustive sweep and frozen trace tests.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, help='Local commit/ref before the optimization')
    parser.add_argument('--godot', type=Path, default=ROOT / '.tools/godot/Godot_v4.7.2-stable_win64_console.exe')
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', '--verify', args.baseline + '^{commit}'], cwd=ROOT, text=True).strip()
    folder = ROOT / '.tools/collision-queries' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
    folder.mkdir(parents=True)
    script = (ROOT / 'tools/collision-query-benchmark.gd.in').read_text(encoding='utf-8')
    for path, filename, class_name in (
        ('src/shared/combat/combat_spatial_index.gd', 'old_spatial_index.gd', 'CombatSpatialIndex'),
        ('src/shared/arena/arena_collision_system.gd', 'old_arena_collision.gd', 'ArenaCollisionSystem'),
    ):
        source = subprocess.check_output(['git', 'show', revision + ':' + path], cwd=ROOT, text=True, encoding='utf-8')
        (folder / filename).write_text(source.replace('class_name ' + class_name + '\n', '', 1), encoding='utf-8')
        script = script.replace('res://.tools/' + filename, 'res://' + (folder / filename).relative_to(ROOT).as_posix())
    (folder / 'fixture.gd').write_text(script, encoding='utf-8')
    process = subprocess.run([str(args.godot.resolve()), '--headless', '--path', str(ROOT), '--log-file', str(folder / 'engine.log'),
                              '--script', 'res://' + (folder / 'fixture.gd').relative_to(ROOT).as_posix()], cwd=ROOT,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace',
                             timeout=60, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    (folder / 'fixture.log').write_text(process.stdout, encoding='utf-8')
    markers = [line.split('=', 1)[1] for line in process.stdout.splitlines() if line.startswith('SSF_SWEEP_MICRO=')]
    errors = [line for line in process.stdout.splitlines() if line.startswith(('ERROR:', 'SCRIPT ERROR:')) and line != 'ERROR: Failed to read the root certificate store.']
    if process.returncode or errors or not markers:
        raise SystemExit(f'Collision benchmark failed; inspect {folder}')
    measurements = json.loads(markers[-1])
    for category in ('ships', 'obstacles'):
        before, after = measurements['before_' + category], measurements['after_' + category]
        if len(before) != 6 or len(after) != 6 or any(a['hits'] != b['hits'] or a['sweeps'] != b['sweeps'] for a, b in zip(before, after)):
            raise SystemExit('Collision workload mismatch: ' + category)
    result = dict(baseline_commit=revision, seed=629914, measurements=measurements,
                  median_usec={name: statistics.median(row['usec'] for row in rows) for name, rows in measurements.items()},
                  scope='Six alternating samples after two warmups; 16 batches of 1024 fixed short sweeps per sample. Includes ship-index rebuild and exact circle tests. Obstacle geometry preparation is excluded. Does not measure full simulation or FPS.')
    (folder / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result['median_usec']))
    print('Evidence:', folder)


if __name__ == '__main__':
    main()
