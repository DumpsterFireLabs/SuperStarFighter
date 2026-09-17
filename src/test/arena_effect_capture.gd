extends SceneTree

# Rendered evidence for the three prototype effects and the real lobby controls.
var output := "res://.tools/arena-captures"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1280, 720)
	root.set_meta("ssf_presentation_capture_resolution", root.size)
	DirAccess.make_dir_recursive_absolute(output)
	var client := (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
	root.add_child(client)
	await process_frame
	client.splash_auto_timer.stop()
	client._dismiss_splash(true)
	client.bridge.session.local_peer_id = 2
	var options := ArenaEffectRules.DEFAULT.duplicate()
	options.mode = ArenaEffectRules.CUSTOM
	client.bridge.session.latest_lobby_state = {"players": [{"peer_id": 2, "display_name": "Host", "ready": false, "is_npc": false, "spectator": false}], "leader_id": 2, "player_limit": 32, "server_capacity": 32, "match_active": false, "arena_effects": options}
	client._on_lobby_state(client.bridge.latest_lobby_state)
	client.connection_controller.lobby._show_lobby_options()
	client.connection_controller.lobby.lobby_options_tabs.current_tab = 2
	await save("settings")
	client.free()
	root.content_scale_size = Vector2i(1280, 720)
	var canvas := Node2D.new()
	canvas.scale = Vector2.ONE * 0.4
	root.add_child(canvas)
	var arena := ArenaView.new()
	canvas.add_child(arena)
	options.mode = ArenaEffectRules.SIGNATURE
	var effects := ArenaEffectState.new()
	for id in [&"twin_suns", &"dead_freight", &"switchyard"]:
		arena.set_map_id(id)
		effects.reset(id, options)
		effects.step(4, 60, {})
		if id == &"dead_freight":
			effects.damage_cover(Vector2(635, 550), 4, 70)
			effects.damage_cover(Vector2(2135, 550), 4, 120)
		arena.set_effect_state(effects.snapshot())
		await save(String(id))
		if id == &"twin_suns":
			effects.step(7, 60, {})
			arena.set_effect_state(effects.snapshot())
			await save("solar_wave")
	canvas.free()
	print("ARENA_CAPTURE_OK")
	quit()

func save(label: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var result := root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	assert(result == OK)
