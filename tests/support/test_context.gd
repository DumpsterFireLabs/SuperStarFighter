class_name TestContext
extends RefCounted

var passed: int = 0
var failed: int = 0


func expect_true(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS: %s" % description)
	else:
		failed += 1
		printerr("FAIL: %s" % description)


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

