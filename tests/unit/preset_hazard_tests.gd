extends RefCounted

const Presets = preload("res://src/shared/lobby/match_presets.gd")
const MapControls = preload("res://src/client/ui/map_pool_controls.gd")


static func run(context: TestContext, parent: Node) -> void:
	_presets(context)
	_validation_and_authority(context)
	_rotation_and_freeze(context)
	_controls(context, parent)


static func _presets(context: TestContext) -> void:
	var baseline: Array[StringName] = [&"core_arena", &"riftline", &"prism_array", &"twin_suns", &"dead_freight", &"longwave_array", &"broken_orbit", &"switchyard", &"relay_zero"]
	var lobby := ServerLobby.new()
	lobby.admit(2, "Host")
	# Repeated transitions exercise resetting prior pool and hazard choices.
	for preset_id in ["chaos", "competitive", "duel", "competitive", "skirmish", "team_objective", "chaos"]:
		context.expect_true(Presets.apply(lobby, 2, preset_id).ok, "%s hazard preset applies" % preset_id)
		var competitive: bool = preset_id == "competitive"
		var chaos: bool = preset_id == "chaos"
		context.expect_equal(lobby.config.map_pool, baseline if competitive else ArenaLayout.map_ids(), "preset restores its advertised map pool")
		context.expect_equal(lobby.config.arena_effects, {"mode": ArenaEffectRules.SIGNATURE if chaos else ArenaEffectRules.OFF, "mask": 7, "frequency": 1, "strength": 1}, "preset restores all optional event settings")
		var world := AuthoritativeWorld.new()
		for peer_id in lobby.players: world.add_peer(peer_id)
		var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 71)
		var visited: Array[StringName] = []
		for round_number in range(1, lobby.config.map_pool.size() + 1):
			coordinator._select_map_for_round(round_number)
			coordinator._prepare_countdown()
			var map_id := coordinator.current_map_id
			context.expect_false(visited.has(map_id), "preset rotation does not repeat before exhausting its pool")
			visited.append(map_id)
			if competitive:
				context.expect_empty(ArenaLayout.movement_fields(map_id), "competitive rotation excludes currents and gravity")
				context.expect_approx(ArenaLayout.contact_damage(map_id), 0, "competitive rotation excludes surface burns")
				context.expect_equal(world.arena_effects.enabled, 0, "competitive countdown initializes no optional or intrinsic events")
				context.expect_empty(world.arena_effects.step(7, 60, world.combatants), "competitive live arena emits no hazard damage")
			else:
				var expected := 0
				if map_id == &"solar_crucible" or (chaos and map_id == &"twin_suns"): expected = ArenaEffectRules.SOLAR
				if chaos and map_id == &"dead_freight": expected = ArenaEffectRules.CARGO
				if chaos and map_id == &"switchyard": expected = ArenaEffectRules.DOORS
				context.expect_equal(world.arena_effects.enabled, expected, "casual preset initializes its advertised signature and intrinsic events")
			context.expect_equal(coordinator.current_state_payload().map_pool, lobby.config.map_pool, "match payload publishes the selected pool")
		visited.sort()
		var advertised := lobby.config.map_pool.duplicate()
		advertised.sort()
		context.expect_equal(visited, advertised, "actual rotation uses exactly the advertised maps")
		if not competitive:
			context.expect_true(String(Presets.find(preset_id).description).contains("intrinsic map hazards active"), "casual preset discloses mandatory hazards")
			world.set_map_id(&"solar_crucible")
			world.arena_effects.reset(world.map_id, lobby.config.arena_effects)
			var pilot: CombatantState = world.combatants[2]
			pilot.position = Vector2(2200, 900)
			pilot.shield.active = false
			var hits := world.arena_effects.step(7, 60, {2: pilot})
			context.expect_true(hits.size() == 1 and hits[0].damage == 16, "advertised intrinsic Crucible flare actually damages an exposed ship")
		context.expect_empty(lobby.config.validate(), "preset leaves a valid complete configuration")


static func _validation_and_authority(context: TestContext) -> void:
	var lobby := ServerLobby.new()
	for peer_id in [2, 3]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		lobby.request_ready(peer_id, true)
	var before := lobby.serialize()
	context.expect_false(lobby.request_map_pool(3, ["core_arena"]).ok, "guest cannot replace the map pool")
	for pool in [[], ["unknown"], ["CORE_ARENA"], ["core_arena", "core_arena"], ["core_arena", &"core_arena"], [42], [null], ["a".repeat(65)], ArenaLayout.map_ids() + [&"core_arena"]]:
		context.expect_false(lobby.request_map_pool(2, pool).ok, "malformed map selection is rejected without fallback")
	context.expect_equal(lobby.serialize(), before, "rejected pool changes preserve readiness, revision and rules")
	var wire_pool: Array = ["switchyard", "core_arena"]
	context.expect_true(lobby.request_map_pool(2, wire_pool).ok, "host accepts valid wire string IDs")
	wire_pool.clear()
	context.expect_equal(lobby.config.map_pool, [&"core_arena", &"switchyard"], "accepted pool is canonical and detached from caller storage")
	context.expect_false(lobby.all_humans_ready(), "changing maps requires humans to ready again")
	for peer_id in [2, 3]: lobby.request_ready(peer_id, true)
	before = lobby.serialize()
	context.expect_false(lobby.request_map_pool(2, ["switchyard", "core_arena"]).changed, "reordering the same membership is a no-op")
	context.expect_equal(lobby.serialize(), before, "idempotent pool requests preserve readiness and revision")
	var copy := lobby.config.duplicate_config()
	copy.map_pool.clear()
	var snapshot: Dictionary = lobby.serialize()
	(snapshot.map_pool as Array).clear()
	context.expect_equal(lobby.config.map_pool.size(), 2, "config and wire snapshots cannot mutate the live pool")
	context.expect_false(copy.validate().is_empty(), "empty map pool fails configuration validation")
	copy.map_pool.assign([&"unknown"])
	context.expect_false(copy.validate().is_empty(), "unknown map pool fails configuration validation")
	context.expect_true(lobby.request_start(2).ok, "ready valid pool starts a match")
	before = lobby.serialize()
	for sender in [2, 3, ServerLobby.OPERATOR_AUTHORITY_ID]:
		context.expect_false(lobby.request_map_pool(sender, ["solar_crucible"]).ok, "map selection is locked for everyone during a match")
		context.expect_false(Presets.apply(lobby, sender, "chaos").ok, "presets cannot replace a running match's hazard contract")
	context.expect_equal(lobby.serialize(), before, "midmatch rejections leave the frozen rules intact")


static func _rotation_and_freeze(context: TestContext) -> void:
	var config := MatchCoordinatorTests._fast_config()
	config.map_pool.assign([&"core_arena", &"switchyard"])
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer_id in [2, 3]:
		lobby.admit(peer_id, "Pilot%d" % peer_id)
		lobby.request_ready(peer_id, true)
		world.add_peer(peer_id)
	lobby.request_start(2)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, 713)
	context.expect_true(coordinator.start(0), "custom pool starts through the production coordinator")
	MatchCoordinatorTests._advance_until_state(world, coordinator, MatchStateMachine.State.COUNTDOWN)
	var first := coordinator.current_map_id
	context.expect_true(config.map_pool.has(first), "first countdown uses a selected map")
	var repeated := AuthoritativeMatchCoordinator.new(lobby, AuthoritativeWorld.new(), 713)
	context.expect_equal(repeated._map_rotation, coordinator._map_rotation, "same seed and pool reproduce rotation order")
	# Prove isolation even from a future accidental mutation behind the command guard.
	lobby.config.map_pool.assign([&"solar_crucible"])
	lobby.config.arena_effects.mode = ArenaEffectRules.SIGNATURE
	for round_number in [1, 2, 3]:
		coordinator._select_map_for_round(round_number)
		coordinator._prepare_countdown()
		context.expect_true(config.map_pool.has(world.map_id), "later rounds use the frozen map selection")
		context.expect_equal(world.arena_effects.enabled, 0, "later heats use frozen optional effects")
		context.expect_equal(coordinator.current_state_payload().map_pool, config.map_pool, "late spectator payload retains the frozen pool")
		var current := world.map_id
		coordinator._select_map_for_round(round_number)
		context.expect_equal(world.map_id, current, "repeated heat keeps the round map")
	context.expect_equal(world.map_id, first, "two-map deck repeats only after exhausting both maps")


static func _controls(context: TestContext, parent: Node) -> void:
	var effects := ArenaEffectControls.new()
	parent.add_child(effects)
	var settings := ArenaEffectRules.DEFAULT.duplicate()
	effects.refresh(settings, true, [&"solar_crucible"])
	context.expect_false(effects.selectors.strength.disabled, "Crucible damage remains editable when optional effects are off")
	context.expect_true(effects.selectors.frequency.disabled, "Crucible random flare timing cannot pretend to use the frequency selector")
	for strength in 3:
		settings.strength = strength
		effects.refresh(settings, true, [&"solar_crucible"])
		var state := ArenaEffectState.new()
		state.reset(&"solar_crucible", settings)
		var ship := CombatantState.create(2, CombatStats.create_base(), Vector2(2200, 900))
		var hits := state.step(7, 60, {2: ship})
		context.expect_true(hits.size() == 1 and hits[0].damage == [8.0, 16.0, 28.0][strength], "intrinsic flare honors the advertised damage selection")
	effects.refresh(settings, false, [&"solar_crucible"])
	context.expect_true(effects.selectors.strength.disabled, "guests and active matches cannot edit intrinsic damage")
	effects.refresh(settings, true, Presets.COMPETITIVE_MAP_POOL)
	context.expect_true(effects.selectors.strength.disabled and effects.selectors.frequency.disabled, "static preset disables irrelevant event controls")
	settings.mode = ArenaEffectRules.SIGNATURE
	effects.refresh(settings, true, [&"twin_suns", &"switchyard"])
	context.expect_false(effects.selectors.strength.disabled or effects.selectors.frequency.disabled, "signature pool enables relevant event controls")
	var maps := MapControls.new()
	parent.add_child(maps)
	maps.refresh([&"core_arena"], settings, true)
	context.expect_true(maps.toggles[&"core_arena"].disabled, "UI keeps at least one map selected")
	context.expect_false(maps.toggles[&"wormhole"].disabled, "host may add an intrinsic map deliberately")
	context.expect_true(maps.descriptions[&"wormhole"].text.contains("lethal horizons"), "map picker discloses Wormhole's lethal mechanic")
	context.expect_true(maps.descriptions[&"solar_tide"].text.contains("current"), "map picker discloses the current")
	context.expect_true(maps.descriptions[&"solar_crucible"].text.contains("surface burns") and maps.descriptions[&"solar_crucible"].text.contains("solar flares"), "map picker discloses both Crucible damage sources")
	maps.refresh(ArenaLayout.map_ids(), settings, false)
	for toggle in maps.toggles.values(): context.expect_true(toggle.disabled, "guest map picker is read-only")
	context.expect_true(MapControls.summary(ArenaLayout.map_ids(), settings).contains("Solar Tide, Wormhole, Solar Crucible"), "lobby summary names mandatory mechanics before readying")
	effects.free()
	maps.free()
	var client = (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	parent.add_child(client)
	client._dismiss_splash(true)
	client.bridge.session.local_peer_id = 2
	var lobby := ServerLobby.new()
	lobby.admit(2, "Host")
	lobby.admit(3, "Guest")
	Presets.apply(lobby, 2, "competitive")
	client.bridge.session.latest_lobby_state = lobby.serialize()
	client._on_lobby_state(client.bridge.latest_lobby_state)
	var screen: Node = client.connection_controller.lobby
	screen._show_lobby_options()
	screen.lobby_options_tabs.current_tab = 3
	context.expect_equal(parent.get_viewport().gui_get_focus_owner(), screen.map_pool_controls.first_editable_control(), "opening MAPS gives keyboard focus to a usable map choice")
	context.expect_true(screen.lobby_rules_label.text.contains("9 maps") and screen.lobby_rules_label.text.contains("Intrinsic mechanics: none"), "competitive lobby shows actual hazard-free pool before readying")
	client.bridge.session.local_peer_id = 3
	client._on_lobby_state(client.bridge.latest_lobby_state)
	screen.lobby_options_tabs.current_tab = 0
	screen.lobby_options_tabs.current_tab = 3
	context.expect_equal(parent.get_viewport().gui_get_focus_owner(), screen.lobby_options_tabs.get_tab_bar(), "guest can browse MAPS without focus entering disabled controls")
	client.free()
