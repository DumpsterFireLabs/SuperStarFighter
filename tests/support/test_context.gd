class_name TestContext
extends RefCounted

const SCRATCH_DIRECTORY := "user://test-scratch"

var passed: int = 0
var failed: int = 0
## Per-assertion PASS lines are printed only with --verbose-tests; the gates
## read TEST_SUMMARY and the FAIL lines.
var verbose: bool = false
var _suite: String = ""
var _section: String = ""
var _failures: PackedStringArray = []


## Names the suite that following assertions belong to, for failure output.
func begin_suite(suite_name: String) -> void:
	_suite = suite_name
	_section = ""


## Names the part of a suite that following assertions belong to, so a
## failure prints as `FAIL [suite › section]: ...`.
func section(section_name: String) -> void:
	_section = section_name


func expect_true(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		if verbose:
			print("PASS: %s" % description)
	else:
		failed += 1
		var location := _suite if _section.is_empty() else "%s › %s" % [_suite, _section]
		var line := "FAIL [%s]: %s" % [location, description] if not location.is_empty() else "FAIL: %s" % description
		_failures.append(line)
		printerr(line)


## Repeats every failure just before the summary, so they need not be found
## among thousands of PASS lines.
func print_failure_recap() -> void:
	if _failures.is_empty():
		return
	printerr("FAILURES (%d):" % _failures.size())
	for line in _failures:
		printerr(line)


func expect_false(condition: bool, description: String) -> void:
	expect_true(not condition, description)


func expect_equal(actual: Variant, expected: Variant, description: String) -> void:
	expect_true(actual == expected, "%s (expected=%s actual=%s)" % [description, expected, actual])


func expect_approx(actual: float, expected: float, description: String, epsilon: float = 0.0001) -> void:
	expect_true(
		absf(actual - expected) <= epsilon,
		"%s (expected≈%.6f actual=%.6f)" % [description, expected, actual]
	)


func expect_empty(values: Variant, description: String) -> void:
	expect_true(values.is_empty(), "%s (actual=%s)" % [description, values])


## A fresh path under user://test-scratch for files a test writes. The runner
## empties the folder before and after the run, so suites need no cleanup of
## their own and nothing lands in the source tree.
func scratch_path(file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH_DIRECTORY))
	return SCRATCH_DIRECTORY.path_join("%d-%s" % [Time.get_ticks_usec(), file_name])


static func clear_scratch() -> void:
	_remove_tree(ProjectSettings.globalize_path(SCRATCH_DIRECTORY))


static func _remove_tree(directory: String) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		return
	for child in DirAccess.get_directories_at(directory):
		_remove_tree(directory.path_join(child))
	for file_name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file_name))
	DirAccess.remove_absolute(directory)
