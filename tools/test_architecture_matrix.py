"""Regressions for mixed-load coverage and the opt-in CPU acceptance lane."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('matrix', ROOT / 'tools/verify-architecture-matrix.py')
matrix = importlib.util.module_from_spec(spec)
spec.loader.exec_module(matrix)
CASES = json.loads(matrix.CASES_PATH.read_text())
HOST = {'cpu': 'Test CPU', 'threads': 16, 'os': 'Windows', 'engine': '4.7.2'}


def sample(case):
    return {'valid': True, 'functional_valid': True, 'timing_valid': True,
            'map': case['map'], 'mode_id': case['mode'], 'humans': 16, 'npcs': 16,
            'active_ticks': 540, 'minimum_alive_before_step': 32,
            'minimum_projectiles_before_step': 1024, 'field_activity_ticks': 400,
            'pulse_activity_ticks': 120,
            'timings': {'samples': 480, 'p95_usec': 15000, 'p99_usec': 18000,
                        'max_usec': 21000, 'over_physics_budget': 30},
            'attribution': {'profiled': False}, 'host': HOST.copy()}


def output(row):
    return '\n'.join(name + '=' + json.dumps(value) for name, value in [
        ('SSF_ARCHITECTURE_MATRIX', row), ('SSF_MATRIX_PHASES', row['attribution']),
        ('SSF_MATRIX_HOST', row['host'])])


class MatrixTests(unittest.TestCase):
    def test_checked_in_reference_matches_the_current_workload(self):
        reference = json.loads((ROOT / 'tests/fixtures/performance/graphite-i7-10700k-windows.json').read_text())
        self.assertEqual(reference['workload_signature'], matrix.workload_signature())
        self.assertEqual(reference['workload_version'], matrix.WORKLOAD_VERSION)
        self.assertEqual(reference['cases'], CASES)
        self.assertEqual(reference['repeats'], 3)
        self.assertEqual(set(reference['timings']), {case['map'] for case in CASES})
        self.assertEqual(matrix.compare_baseline(reference, reference), [])

    def test_roster_covers_all_modes_and_intrinsic_hazards(self):
        self.assertEqual(len(CASES), 8)
        self.assertEqual({case['mode'] for case in CASES}, set(range(5)))
        by_map = {case['map']: case for case in CASES}
        self.assertEqual(len(by_map), len(CASES))
        for name in ('solar_tide', 'wormhole', 'solar_crucible'):
            self.assertTrue(by_map[name]['field'])
        self.assertTrue(by_map['solar_crucible']['solar'])
        self.assertTrue(by_map['twin_suns']['solar'])
        for case in CASES:
            self.assertTrue((ROOT / 'resources/maps' / (case['map'] + '.tres')).exists())

    def test_correctness_does_not_fail_on_cpu_overruns(self):
        row = sample(CASES[-1])
        row['timings']['p99_usec'] = 100000
        self.assertTrue(matrix.parse_result(output(row), 0, CASES[-1])['valid'])

    def test_missing_mechanics_wrong_map_or_reduced_load_fail(self):
        for key, value in [('field_activity_ticks', 0), ('pulse_activity_ticks', 0),
                           ('minimum_alive_before_step', 31), ('minimum_projectiles_before_step', 100),
                           ('humans', 0), ('npcs', 0), ('active_ticks', 120),
                           ('map', 'core_arena'), ('mode_id', 0), ('functional_valid', False)]:
            with self.subTest(key=key):
                row = sample(CASES[-1])
                row[key] = value
                self.assertFalse(matrix.parse_result(output(row), 0, CASES[-1])['valid'])

    def test_bad_samples_and_engine_errors_fail_even_with_pass_marker(self):
        for value in (float('nan'), float('inf'), -1, '15000', None):
            row = sample(CASES[-1])
            row['timings']['p95_usec'] = value
            self.assertFalse(matrix.parse_result(output(row), 0, CASES[-1])['valid'])
        row = sample(CASES[-1])
        row['timings']['samples'] = 0
        self.assertFalse(matrix.parse_result(output(row), 0, CASES[-1])['valid'])
        row = sample(CASES[-1])
        for error in ('ERROR: fixture broke', '  SCRIPT ERROR: fixture broke'):
            self.assertFalse(matrix.parse_result(output(row) + '\n' + error, 0, CASES[-1])['valid'])
        self.assertFalse(matrix.parse_result(output(row), 1, CASES[-1])['valid'])
        self.assertTrue(matrix.parse_result(output(row) + '\nERROR: Failed to read the root certificate store.', 0, CASES[-1])['valid'])

    def test_missing_duplicate_or_malformed_markers_fail(self):
        row = sample(CASES[-1])
        for text in ('', output(row) + '\nSSF_ARCHITECTURE_MATRIX={}', 'SSF_ARCHITECTURE_MATRIX=broken'):
            with self.assertRaises(ValueError):
                matrix.parse_result(text, 0, CASES[-1])

    def baseline(self):
        return matrix.make_baseline([sample(case) for _ in range(3) for case in CASES], 'test-rig', CASES, 3)

    def test_baseline_uses_repeated_unprofiled_complete_work(self):
        rows = [sample(case) for _ in range(3) for case in CASES]
        rows[0]['timings']['p95_usec'] = 90000
        baseline = matrix.make_baseline(rows, 'test-rig', CASES, 3)
        self.assertEqual(baseline['timings']['core_arena']['p95_usec'], 15000)
        for change in ('missing', 'duplicate', 'failure', 'profile', 'host'):
            bad = copy.deepcopy(rows)
            if change == 'missing': bad.pop()
            if change == 'duplicate': bad[-1] = copy.deepcopy(bad[0])
            if change == 'failure': bad[0]['valid'] = False
            if change == 'profile': bad[0]['attribution']['profiled'] = True
            if change == 'host': bad[0]['host']['cpu'] = 'Other CPU'
            with self.subTest(change=change), self.assertRaises(ValueError):
                matrix.make_baseline(bad, 'test-rig', CASES, 3)
        for label, repeats in [('', 3), ('test-rig', 1)]:
            with self.assertRaises(ValueError):
                matrix.make_baseline(rows, label, CASES, repeats)

    def test_cpu_regression_is_separate_and_does_not_relax_reference(self):
        baseline = self.baseline()
        original = copy.deepcopy(baseline)
        current = copy.deepcopy(baseline)
        self.assertEqual(matrix.compare_baseline(current, baseline), [])
        current['timings']['wormhole']['p95_usec'] = 18000
        failures = matrix.compare_baseline(current, baseline)
        self.assertEqual(len(failures), 1)
        self.assertIn('wormhole p95_usec', failures[0])
        self.assertEqual(baseline, original)

    def test_incompatible_hardware_engine_or_workload_is_rejected(self):
        baseline = self.baseline()
        for key in ('hardware_label', 'host', 'workload_version', 'workload_signature', 'cases', 'repeats'):
            current = copy.deepcopy(baseline)
            current[key] = 'different'
            with self.subTest(key=key), self.assertRaises(ValueError):
                matrix.compare_baseline(current, baseline)
        for invalid in (0, -1, float('nan'), float('inf')):
            bad = copy.deepcopy(baseline)
            bad['timings']['wormhole']['p95_usec'] = invalid
            with self.assertRaises(ValueError):
                matrix.compare_baseline(baseline, bad)

    def test_cli_rejects_unsafe_timing_combinations_before_running_engine(self):
        for arguments in [ ['--strict-physics-budget'], ['--record-baseline', 'unused.json'],
                           ['--hardware-label', 'rig', '--profile', '--baseline', 'unused.json'],
                           ['--hardware-label', 'rig', '--profile', '--strict-physics-budget'],
                           ['--hardware-label', 'rig', '--case', '0', '--baseline', 'unused.json'],
                           ['--case', '8'], ['--case', '-1'],
                           ['--hardware-label', 'rig', '--record-baseline', str(matrix.CASES_PATH)]]:
            result = subprocess.run([sys.executable, str(ROOT / 'tools/verify-architecture-matrix.py'), *arguments], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
