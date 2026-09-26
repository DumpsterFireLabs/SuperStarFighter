extends Node

## Asks GitHub for the latest published release once and reports it when it is
## newer than the running build. Failures are silent: an offline player should
## never see an error just because the release feed was unreachable.

signal update_available(version: String, url: String)

const LATEST_RELEASE_URL: String = "https://api.github.com/repos/DumpsterFireLabs/SuperStarFighter/releases/latest"
const REQUEST_TIMEOUT_SECONDS: float = 8.0

var _request: HTTPRequest


func check(current_version: String = GameConstants.GAME_VERSION) -> void:
	if _request != null:
		return
	_request = HTTPRequest.new()
	_request.name = "LatestReleaseRequest"
	_request.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(_request)
	_request.request_completed.connect(_on_request_completed.bind(current_version))
	var headers := PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: SuperStarFighter/%s" % current_version])
	if _request.request(LATEST_RELEASE_URL, headers) != OK:
		_finish()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, current_version: String) -> void:
	_finish()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var release: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not release is Dictionary:
		return
	var tag := str(release.get("tag_name", "")).strip_edges()
	if tag.is_empty() or bool(release.get("draft", false)):
		return
	if is_newer(tag, current_version):
		update_available.emit(tag.trim_prefix("v"), str(release.get("html_url", "")))


func _finish() -> void:
	if _request != null:
		_request.queue_free()


## Semantic-version comparison that understands this project's tags, e.g.
## "v0.1.0-beta.18". A release without a pre-release suffix outranks any
## pre-release of the same core version.
static func is_newer(candidate: String, current: String) -> bool:
	return compare_versions(candidate, current) > 0


static func compare_versions(a: String, b: String) -> int:
	var left := _split_version(a)
	var right := _split_version(b)
	var core_order := _compare_identifiers(left[0], right[0], true)
	if core_order != 0:
		return core_order
	var left_pre: PackedStringArray = left[1]
	var right_pre: PackedStringArray = right[1]
	if left_pre.is_empty() or right_pre.is_empty():
		return int(left_pre.is_empty()) - int(right_pre.is_empty())
	return _compare_identifiers(left_pre, right_pre, false)


static func _split_version(version: String) -> Array:
	var cleaned := version.strip_edges().trim_prefix("v").get_slice("+", 0)
	var dash := cleaned.find("-")
	var core := cleaned if dash < 0 else cleaned.substr(0, dash)
	var pre := PackedStringArray() if dash < 0 else cleaned.substr(dash + 1).split(".", false)
	return [core.split(".", false), pre]


static func _compare_identifiers(left: PackedStringArray, right: PackedStringArray, pad_with_zero: bool) -> int:
	var count := maxi(left.size(), right.size()) if pad_with_zero else mini(left.size(), right.size())
	for index in count:
		var l := left[index] if index < left.size() else "0"
		var r := right[index] if index < right.size() else "0"
		if l.is_valid_int() and r.is_valid_int():
			if l.to_int() != r.to_int():
				return signi(l.to_int() - r.to_int())
		elif l.is_valid_int() != r.is_valid_int():
			return -1 if l.is_valid_int() else 1
		elif l != r:
			return -1 if l < r else 1
	return 0 if pad_with_zero else signi(left.size() - right.size())
