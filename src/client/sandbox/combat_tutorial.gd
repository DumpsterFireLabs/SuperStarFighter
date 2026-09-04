extends RefCounted

enum Step { MOVE, FIRE, RELOAD, SHIELD, PERFECT_GUARD, ABILITY, DRAFT, COMPLETE }
const DRAFT_CARDS: Array[StringName] = [&"reinforced_hull", &"rapid_cycling", &"quick_loader"]
const TITLES: Array[String] = ["Move and aim", "Land a shot", "Reload your magazine", "Face the incoming fire", "Time a Perfect Guard", "Select and activate an ability", "Choose a draft upgrade", "Training complete"]
var lab: Node
var active: bool = false
var step: Step = Step.MOVE
var panel: PanelContainer
var title: Label
var instructions: Label
var progress: Label
var choices: VBoxContainer
var restart_button: Button
var retry_button: Button
var exit_button: Button
var saved_setup: Dictionary = {}
var movement_distance: float = 0.0
var previous_position: Vector2
var hit_confirmed: bool = false
var block_confirmed: bool = false
var perfect_confirmed: bool = false
var reload_started: bool = false
var selected_ability: bool = false
var chosen_card: StringName = &""


func configure(sandbox: Node, hud: Control) -> void:
	lab = sandbox
	panel = PanelContainer.new()
	panel.name = "GuidedIntroduction"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101b2df5")
	style.border_color = Color("42e8ff")
	style.set_border_width_all(1)
	style.set_content_margin_all(12.0)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	var layout_root := VBoxContainer.new()
	panel.add_child(layout_root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	title = _label(content, 21)
	instructions = _label(content, 16)
	progress = _label(content, 16)
	choices = VBoxContainer.new()
	content.add_child(choices)
	var actions := HBoxContainer.new()
	layout_root.add_child(actions)
	retry_button = _button(actions, "Retry step", retry_step)
	restart_button = _button(actions, "Restart lesson", start)
	exit_button = _button(actions, "Skip to lab", stop)
	panel.hide()


func start() -> void:
	if not active:
		saved_setup = {"build": lab.build.duplicate(), "count": lab.target_count, "health": lab.target_health, "distance": lab.target_distance, "shield": lab.targets_shielding, "fire": lab.targets_firing, "move": lab.targets_moving}
	active = true
	chosen_card = &""
	lab.load_preset(0)
	lab.set_editor_open(false)
	lab.editor_button.hide()
	panel.show()
	_enter_step(Step.MOVE)


func stop() -> void:
	if not active:
		return
	active = false
	panel.hide()
	lab.build = saved_setup.build.duplicate()
	lab._apply_build()
	lab.set_target_settings(saved_setup.count, saved_setup.health, saved_setup.distance, saved_setup.shield, saved_setup.fire, saved_setup.move)
	lab.editor_button.show()
	lab.set_editor_open(true)


func blocks_simulation() -> bool:
	return active and step >= Step.DRAFT


func retry_step() -> void:
	if active and step < Step.DRAFT:
		_enter_step(step)


func _enter_step(value: Step) -> void:
	step = value
	lab.combat_input_armed = false
	hit_confirmed = false
	block_confirmed = false
	perfect_confirmed = false
	reload_started = false
	selected_ability = false
	movement_distance = 0.0
	if step == Step.RELOAD:
		# Keep the magazine spent in the previous step; retry also leaves a
		# reloadable magazine, without asking the learner to waste a shot.
		lab.targets_firing = false
		lab.player.combatant.weapon.reloading = false
		lab.player.combatant.weapon.ammunition = mini(lab.player.combatant.weapon.ammunition, lab.derived_stats.magazine_size - 1)
	elif step < Step.DRAFT:
		lab.set_target_settings(1, 600.0, 600.0 if step in [Step.SHIELD, Step.PERFECT_GUARD] else 300.0, false, step in [Step.SHIELD, Step.PERFECT_GUARD], false)
		if step in [Step.SHIELD, Step.PERFECT_GUARD]:
			# Slow, low-damage practice rounds still use real firing, geometry,
			# shield arcs and the unmodified Perfect Guard timing window.
			var target: CombatantState = lab.targets[0].combatant
			target.stats.projectile_speed = 250.0
			target.stats.projectile_damage = 5.0
			target.stats.fire_rate = 0.5
			target.weapon.cooldown_remaining = 1.0
		if step == Step.ABILITY:
			lab.build = {&"afterburner": 1, &"mine_layer": 1}
			lab._apply_build()
			lab.selected_special_slot = 1
	previous_position = lab.player.combatant.position
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	if step == Step.DRAFT:
		for card_id in DRAFT_CARDS:
			var card: CardDefinition = lab.catalog.get_card(card_id)
			var changes := PackedStringArray()
			for row in StatSystem.compare_pick(lab.build, card, lab.catalog):
				changes.append("%s %.2f → %.2f" % [String(row.property).replace("_", " "), row.before, row.after])
			_button(choices, card.display_name, choose_card.bind(card_id))
			_label(choices, 15).text = ", ".join(changes)
		choices.get_child(0).grab_focus()
	retry_button.visible = step < Step.DRAFT
	exit_button.text = "Return to lab" if step == Step.COMPLETE else "Skip to lab"
	if step == Step.COMPLETE:
		exit_button.grab_focus()
	refresh()


func observe_feedback(event: Dictionary) -> void:
	if not active:
		return
	hit_confirmed = hit_confirmed or int(event.get("hit_count", 0)) > 0
	block_confirmed = block_confirmed or int(event.get("guard_count", 0)) > 0
	perfect_confirmed = perfect_confirmed or (int(event.get("guard_count", 0)) > 0 and event.get("last_guard_reason", "") == "perfect_guard")


func after_step(frame: PlayerInputFrame) -> void:
	if not active or blocks_simulation():
		return
	var state: CombatantState = lab.player.combatant
	if not state.alive:
		retry_step()
		return
	var advance := false
	match step:
		Step.MOVE:
			if not frame.movement.is_zero_approx():
				movement_distance += state.position.distance_to(previous_position)
			advance = movement_distance >= 120.0
		Step.FIRE: advance = hit_confirmed
		Step.RELOAD:
			reload_started = reload_started or (frame.manual_reload and state.weapon.reloading)
			advance = reload_started and not state.weapon.reloading and state.weapon.ammunition == state.stats.magazine_size
		Step.SHIELD: advance = block_confirmed
		Step.PERFECT_GUARD: advance = perfect_confirmed
		Step.ABILITY:
			selected_ability = selected_ability or lab.selected_special_slot == 0
			advance = selected_ability and frame.special_slot == 0 and state.afterburner_remaining > 0.0
	previous_position = state.position
	if advance:
		_enter_step(step + 1 as Step)
	else:
		refresh()


func choose_card(card_id: StringName) -> void:
	if not active or step != Step.DRAFT or not card_id in DRAFT_CARDS:
		return
	chosen_card = card_id
	lab.build[card_id] = int(lab.build.get(card_id, 0)) + 1
	lab._apply_build()
	_enter_step(Step.COMPLETE)


func refresh() -> void:
	if not active:
		return
	title.text = "GUIDED INTRODUCTION · %d/7 · %s" % [mini(step + 1, 7), TITLES[step]]
	var movement := "WASD"
	if lab.input_profiles != null:
		movement = lab.input_profiles.binding_text(&"move_up") + " / " + lab.input_profiles.binding_text(&"move_left") + " / " + lab.input_profiles.binding_text(&"move_down") + " / " + lab.input_profiles.binding_text(&"move_right")
	var texts: Array[String] = [
		"Move with %s and aim at the target. Relative flight keeps movement aligned with the screen; Newtonian flight rotates thrust with your aim. Choose your mode in Settings." % movement,
		"Aim at the stationary target and fire (%s). Progress requires confirmed hull damage; a missed shot does not count." % _binding(&"fire", "Left mouse"),
		"Press %s and wait for a full magazine. Reloading prevents firing; an empty magazine reloads automatically." % _binding(&"manual_reload", "R"),
		"Aim toward the target, then hold shield (%s) to block a round. Your shield only covers the facing arc, drains energy, and prevents firing." % _binding(&"shield", "Right mouse"),
		"Release shield, watch the slow round approach, then raise it just before impact (%s). A Perfect Guard uses less shield energy. Keep facing the target; retry as often as needed." % _binding(&"shield", "Right mouse"),
		"Select Afterburner with %s / %s, then activate (%s). One press uses only the selected ability; mines have charges, Afterburner has a cooldown." % [_binding(&"special_previous", "Q"), _binding(&"special_next", "E"), _binding(&"special", "Shift")],
		"Before each round, draft an upgrade for your build. Choose one below; the preview shows the effective stat change. Practice is paused.",
		"You moved, landed a shot, reloaded, blocked, timed a Perfect Guard, selected an ability and drafted %s. Return to the lab to experiment; your previous lab setup will be restored." % (lab.catalog.get_card(chosen_card).display_name if chosen_card != &"" else "an upgrade"),
	]
	instructions.text = texts[step]
	progress.text = "Distance flown: %.0f / 120" % minf(movement_distance, 120.0) if step == Step.MOVE else "Reloading…" if step == Step.RELOAD and reload_started else "Waiting for your draft choice" if step == Step.DRAFT else "All seven actions complete" if step == Step.COMPLETE else "Perform the action to continue · Retry step resets this exercise"
	layout()


func layout() -> void:
	if panel == null:
		return
	panel.size = Vector2(minf(480.0, lab.hud_root.size.x * 0.44), minf(360.0, maxf(lab.hud_root.size.y - 132.0, 120.0)))
	panel.position = Vector2(lab.hud_root.size.x - panel.size.x, maxf(132.0, lab.hud_root.size.y - panel.size.y))


func _binding(action: StringName, fallback: String) -> String:
	return lab.input_profiles.binding_text(action) if lab.input_profiles != null else fallback


func _label(parent: Node, font_size: int) -> Label:
	var result := Label.new()
	result.add_theme_font_size_override("font_size", font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result


func _button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result
