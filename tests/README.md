# Where test code lives

There are three kinds of test code. Put new code in the kind that matches how it runs.

| Folder | What it holds | How it runs |
| --- | --- | --- |
| `tests/unit/` | Assertion suites: one `<name>_tests.gd` file with `static func run(context: TestContext[, parent: Node])`. Fast, deterministic, single process. | `.\tools\run-tests.ps1` (optionally `-Filter <text>`, `-VerboseTests`). Every suite must be listed in `SUITES` in `src/test/test_runner.gd`; the runner fails for a file that is not. |
| `tests/support/` | `TestContext` (assertions, suite and section labels, `scratch_path()`) and shared fixtures. | Used by the unit suites. |
| `tests/fixtures/` | Reviewed baselines such as map geometry and stat derivation hashes. | Read by unit suites; change only with a deliberate content change. |
| `src/test/` | The unit runner, the bot client, verifiers and benchmarks that start real servers, clients or rendered frames. | Launched by `tools/verify-*.ps1`, `tools/verify-*.py`, `tools/ci-acceptance.py` or directly with `godot --headless --path . --script res://src/test/<name>.gd`. |
| `tests/integration/` | Admin-console probes. | Launched by their tool scripts. |

Tests that write files use `context.scratch_path("name.cfg")`, which points into `user://test-scratch/`. The runner empties that folder before and after each run, so suites never write into the source tree.

Scripts under `src/test/` are stripped from exported builds by the export allowlists, like everything else outside the shipping roots.
