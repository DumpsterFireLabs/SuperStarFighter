class_name TestContext
extends RefCounted

var passed: int = 0
var failed: int = 0
var _suite: String = ""
var _failures: PackedStringArray = []


## Names the suite that following assertions belong to, for failure output.
func begin_suite(suite_name: String) -> void:
	_suite = suite_name


func expect_true(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: %s" % description)
	else:
		failed += 1
		var line := "FAIL [%s]: %s" % [_suite, description] if not _suite.is_empty() else "FAIL: %s" % description
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

