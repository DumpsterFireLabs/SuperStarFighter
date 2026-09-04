class_name KillFeed
extends Control

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")

const MAX_ENTRIES: int = 6
const ENTRY_LIFETIME_SECONDS: float = 5.0
const FADE_SECONDS: float = 0.75
const FEED_WIDTH: float = 420.0
const SCREEN_MARGIN: float = 24.0

var entries_container: VBoxContainer
var entries: Array[Dictionary] = []
var _seen_keys: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries_container = VBoxContainer.new()
	entries_container.name = "KillFeedEntries"
	entries_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	entries_container.offset_left = -FEED_WIDTH - SCREEN_MARGIN
	entries_container.offset_top = SCREEN_MARGIN
	entries_container.offset_right = -SCREEN_MARGIN
	entries_container.add_theme_constant_override("separation", 8)
	entries_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(entries_container)
	visible = false


func add_eliminations(
	eliminations: Array,
	server_tick: int,
	local_peer_id: int,
	players: Array
) -> void:
	for elimination_value in eliminations:
		var elimination := elimination_value as Dictionary
		var victim_id := int(elimination.get("victim_id", 0))
		if victim_id == 0:
			continue
		var killer_id := int(elimination.get("killer_id", 0))
		var reason := String(elimination.get("reason", "combat"))
		var key := "%d:%d:%d:%s" % [server_tick, killer_id, victim_id, reason]
		if _seen_keys.has(key):
			continue
		_seen_keys[key] = true
		var node := _create_entry(killer_id, victim_id, reason, local_peer_id, players)
		entries_container.add_child(node)
		entries_container.move_child(node, 0)
		entries.push_front({
			"key": key,
			"node": node,
			"remaining": ENTRY_LIFETIME_SECONDS,
			"killer_id": killer_id,
			"victim_id": victim_id,
			"reason": reason,
		})
		while entries.size() > MAX_ENTRIES:
			_remove_entry(entries.size() - 1)


func set_match_state(state_name: String) -> void:
	if state_name in ["LOBBY", "DRAFT", "COUNTDOWN"]:
		clear()
	visible = state_name in ["ACTIVE_HEAT", "HEAT_RESULT", "ROUND_RESULT"]


func clear() -> void:
	for entry in entries:
		var node := entry.get("node") as Control
		if node != null:
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	entries.clear()
	_seen_keys.clear()


func advance(delta: float) -> void:
	for index in range(entries.size() - 1, -1, -1):
		var entry := entries[index] as Dictionary
		var remaining := float(entry.get("remaining", 0.0)) - maxf(delta, 0.0)
		entry["remaining"] = remaining
		var node := entry.get("node") as Control
		if node != null:
			node.modulate.a = clampf(remaining / FADE_SECONDS, 0.0, 1.0) if remaining < FADE_SECONDS else 1.0
		entries[index] = entry
		if remaining <= 0.0:
			_remove_entry(index)


func _process(delta: float) -> void:
	advance(delta)


func _create_entry(
	killer_id: int,
	victim_id: int,
	reason: String,
	local_peer_id: int,
	players: Array
) -> PanelContainer:
	var local_involved := killer_id == local_peer_id or victim_id == local_peer_id
	var accent := DesignTokensScript.TEXT_SECONDARY if local_involved else DesignTokensScript.DISABLED
	var panel := PanelContainer.new()
	panel.name = "KillFeedEntry"
	panel.custom_minimum_size = Vector2(FEED_WIDTH, 44.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _entry_style(accent, local_involved))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var killer_label := _entry_label(HORIZONTAL_ALIGNMENT_RIGHT)
	var action_label := _entry_label(HORIZONTAL_ALIGNMENT_CENTER)
	var victim_label := _entry_label(HORIZONTAL_ALIGNMENT_LEFT)
	killer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	killer_label.custom_minimum_size.x = 0.0
	killer_label.size_flags_stretch_ratio = 1.0
	action_label.name = "EventMeaning"
	action_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	victim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	victim_label.custom_minimum_size.x = 0.0
	victim_label.size_flags_stretch_ratio = 1.0
	var victim := _player_identity(victim_id, players)
	victim_label.text = String(victim.get("display_name", "Pilot %d" % victim_id))
	victim_label.add_theme_color_override("font_color", _identity_color(victim))
	if reason == "disconnect":
		killer_label.text = victim_label.text
		killer_label.add_theme_color_override("font_color", _identity_color(victim))
		action_label.text = "left"
		action_label.add_theme_color_override("font_color", DesignTokensScript.TEXT_MUTED)
		victim_label.text = ""
		victim_label.hide()
	elif killer_id == 0:
		killer_label.text = "Arena"
		killer_label.add_theme_color_override("font_color", DesignTokensScript.WARNING)
		action_label.text = "defeated"
		action_label.add_theme_color_override("font_color", DesignTokensScript.WARNING)
	else:
		var killer := _player_identity(killer_id, players)
		killer_label.text = String(killer.get("display_name", "Pilot %d" % killer_id))
		killer_label.add_theme_color_override("font_color", _identity_color(killer))
		action_label.text = "defeated"
		action_label.add_theme_color_override("font_color", DesignTokensScript.DANGER)
	row.add_child(killer_label)
	row.add_child(action_label)
	row.add_child(victim_label)
	if local_involved:
		var marker := Label.new()
		marker.text = "◆"
		marker.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
		row.add_child(marker)
	panel.set_meta("killer_id", killer_id)
	panel.set_meta("victim_id", victim_id)
	panel.set_meta("reason", reason)
	panel.set_meta("local_involved", local_involved)
	return panel


func _entry_label(alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _player_identity(peer_id: int, players: Array) -> Dictionary:
	for player_value in players:
		var player := player_value as Dictionary
		if int(player.get("peer_id", 0)) == peer_id:
			return player
	return {}


func _identity_color(identity: Dictionary) -> Color:
	return Color.from_string(
		"#%s" % String(identity.get("ship_color", "f4fbff")),
		DesignTokensScript.TEXT_PRIMARY
	)


func _entry_style(accent: Color, emphasized: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(DesignTokensScript.SURFACE, 0.92)
	style.border_color = Color(accent, 0.95 if emphasized else 0.62)
	style.set_border_width_all(1)
	style.border_width_left = 4 if emphasized else 1
	style.set_corner_radius_all(DesignTokensScript.RADIUS_CONTROL)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _remove_entry(index: int) -> void:
	var entry := entries[index] as Dictionary
	_seen_keys.erase(String(entry.get("key", "")))
	var node := entry.get("node") as Control
	if node != null:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
	entries.remove_at(index)
