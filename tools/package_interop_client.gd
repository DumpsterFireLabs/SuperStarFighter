extends SceneTree
var welcomed := false
var snapshots := 0
var recoveries := 0
var bridge: NetworkBridge
func _initialize() -> void:
    _run.call_deferred()
func _run() -> void:
    var port := 18375
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--port="): port = int(arg.get_slice("=", 1))
    root.set_meta("ssf_command_line", CommandLineConfig.parse(PackedStringArray([])))
    var main := (load("res://scenes/client/client_main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    current_scene = main
    bridge = main.bridge
    bridge.client_connected.connect(func(_id: int) -> void: welcomed = true)
    bridge.client_lobby_updated.connect(_lobby)
    bridge.client_snapshot_received.connect(func(decoded: Dictionary) -> void:
        if not decoded.states.is_empty() and decoded.states[0].has("life_generation"):
            snapshots += 1
    )
    bridge.client_projectile_correction_received.connect(func(decoded: Dictionary) -> void:
        if bool(decoded.get("complete_snapshot", false)): recoveries += 1
    )
    if bridge.start_client("127.0.0.1", port, "PackageReview", GameConstants.PROTOCOL_VERSION, "review-package-smoke") != OK:
        quit(1)
        return
    await create_timer(18.0).timeout
    var ok := welcomed and snapshots >= 20 and recoveries >= 1
    print("SSF_PACKAGE_INTEROP=" + JSON.stringify({"ok":ok,"protocol":GameConstants.PROTOCOL_VERSION,"packet":NetworkProtocol.PACKET_VERSION,"welcomed":welcomed,"snapshots":snapshots,"full_recoveries":recoveries,"shipping":OS.has_feature("ssf_shipping")}))
    bridge.stop()
    main.free()
    await process_frame
    quit(0 if ok else 1)
func _lobby(state: Dictionary) -> void:
    if not welcomed or bool(state.get("match_active", false)): return
    if not bool(state.get("npcs_enabled", false)):
        bridge.send_npcs_enabled(true)
        return
    if int(state.get("player_limit", 0)) != 2:
        bridge.send_player_limit(2)
        return
    for player: Dictionary in state.get("players", []):
        if int(player.peer_id) == bridge.local_peer_id and not bool(player.ready):
            bridge.send_ready_state(true)
            return
    if bool(state.get("all_humans_ready", false)): bridge.send_start_match()
