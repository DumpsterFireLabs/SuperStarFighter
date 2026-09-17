extends RefCounted

## Shared session observations and rendering surface; contains no presentation owners.
signal presentation_event(event_name: StringName, payload: Dictionary)
const AccessibilityPreferencesScript = preload("res://src/client/presentation/accessibility_preferences.gd")
var surface: Node2D
var camera: Camera2D
var bridge: NetworkBridge
var input_profiles: Node
var local_peer_id: int = 0
var _network_active: bool = false
var accessibility_settings: Dictionary = AccessibilityPreferencesScript.DEFAULTS.duplicate()
var latest_server_tick: int = 0
var match_state := preload("res://src/client/network/client_match_state.gd").new()
var match_payload: Dictionary:
	get: return match_state.payload
	set(value): match_state.replace(value)
var controls_enabled: bool = false
var match_paused: bool = false
var card_catalog := CardCatalog.create_default()


static func now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func visible_world_rect() -> Rect2:
	if camera == null:
		return Rect2(Vector2.ZERO, GameConstants.ARENA_SIZE)
	var zoom := Vector2(maxf(camera.zoom.x, 0.001), maxf(camera.zoom.y, 0.001))
	var world_size := surface.get_viewport_rect().size / zoom
	return Rect2(camera.position - world_size * 0.5, world_size)
