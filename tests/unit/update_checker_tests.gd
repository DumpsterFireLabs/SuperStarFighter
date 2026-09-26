extends RefCounted

const UpdateChecker = preload("res://src/client/network/update_checker.gd")


static func run(context: TestContext) -> void:
	context.expect_true(UpdateChecker.is_newer("v0.1.0-beta.19", "0.1.0-beta.18"), "a later beta tag is an update")
	context.expect_true(UpdateChecker.is_newer("v0.1.0-beta.10", "0.1.0-beta.9"), "beta numbers compare numerically, not alphabetically")
	context.expect_false(UpdateChecker.is_newer("v0.1.0-beta.16", "0.1.0-beta.18"), "an older release never prompts a newer build")
	context.expect_false(UpdateChecker.is_newer("v0.1.0-beta.18", "0.1.0-beta.18"), "the running release is not an update")
	context.expect_true(UpdateChecker.is_newer("v0.1.0", "0.1.0-beta.18"), "a final release outranks its betas")
	context.expect_false(UpdateChecker.is_newer("v0.1.0-beta.30", "0.1.0"), "a beta never outranks the matching final release")
	context.expect_true(UpdateChecker.is_newer("v0.2.0-beta.1", "0.1.9"), "a higher core version wins regardless of pre-release")
	context.expect_true(UpdateChecker.is_newer("v0.1.0-rc.1", "0.1.0-beta.18"), "release candidates follow betas")
	context.expect_false(UpdateChecker.is_newer("v0.1", "0.1.0"), "missing patch numbers count as zero")
	context.expect_equal(UpdateChecker.compare_versions("0.1.0-beta.18+build.7", "0.1.0-beta.18"), 0, "build metadata is ignored")
