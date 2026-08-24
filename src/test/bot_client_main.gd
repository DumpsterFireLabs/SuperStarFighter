extends Node

var bridge: NetworkBridge
var input_sequence: int = 0
var client_tick: int = 0
var send_accumulator: float = 0.0
var elapsed: float = 0.0
var welcomed: bool = false
var snapshot_count: int = 0
var observed_ack: bool = false
var observed_movement: bool = false
var observed_aim: bool = false
var observed_shield: bool = false
var observed_correction: bool = false


func _ready() -> void:
	var configuration: Dictionary = get_tree().root.get_meta("ssf_command_line", {})
	bridge = NetworkBridge.new()
	bridge.name = "NetworkBridge"
	add_child(bridge)
	bridge.client_connected.connect(_on_welcome)
	bridge.client_lobby_updated.connect(_on_lobby_state)
	bridge.client_snapshot_received.connect(_on_snapshot)
	bridge.client_projectile_batch_received.connect(_on_projectile_batch)
	bridge.client_projectile_correction_received.connect(_on_projectile_correction)
	bridge.client_rejected.connect(_on_rejected)
	bridge.client_connection_lost.connect(_on_connection_lost)
	var connect_error := bridge.start_client(
		configuration.get("host", "127.0.0.1"),
		configuration.get("port", GameConstants.DEFAULT_PORT),
		configuration.get("bot_name", "FoundationBot"),
		configuration.get("test_protocol_version", GameConstants.PROTOCOL_VERSION)
	)
	if connect_error != OK:
		push_error(bridge.last_error)
		get_tree().quit(1)
		return
	print(
		"SSF_MODE_READY=bot_client name=%s host=%s port=%d" % [
			configuration.get("bot_name", "FoundationBot"),
			configuration.get("host", "127.0.0.1"),
			configuration.get("port", GameConstants.DEFAULT_PORT),
		]
	)


func _physics_process(delta: float) -> void:
	if not welcomed:
		return
	elapsed += delta
	send_accumulator += delta
	var send_interval := 1.0 / GameConstants.INPUT_SEND_RATE
	while send_accumulator >= send_interval:
		send_accumulator -= send_interval
		input_sequence = SequenceMath.increment(input_sequence)
		client_tick = SequenceMath.increment(client_tick)
		var frame := PlayerInputFrame.new(
			input_sequence,
			client_tick,
			Vector2(sin(elapsed * 0.7) * 0.65, -0.75).limit_length(1.0),
			fposmod(elapsed * 0.8, TAU),
			fmod(elapsed, 1.0) < 0.7,
			fmod(elapsed, 5.0) > 4.2
		)
		bridge.send_input(frame)


func _on_welcome(peer_id: int) -> void:
	welcomed = true
	print("SSF_BOT_WELCOME peer_id=%d" % peer_id)


func _on_lobby_state(state: Dictionary) -> void:
	print("SSF_BOT_LOBBY revision=%d players=%d leader=%d" % [state.get("revision", 0), (state.get("players", []) as Array).size(), state.get("leader_id", 0)])
	if welcomed and int(state.get("leader_id", 0)) == bridge.local_peer_id and (state.get("players", []) as Array).size() >= 2 and not bool(state.get("match_active", false)):
		bridge.send_start_match()


func _on_snapshot(decoded: Dictionary) -> void:
	snapshot_count += 1
	if snapshot_count == 1:
		print("SSF_BOT_SNAPSHOT server_tick=%d players=%d ack=%d rtt_ms=%d" % [decoded.server_tick, (decoded.states as Array).size(), decoded.acknowledged_input, bridge.get_round_trip_time_ms()])
	if not observed_ack and int(decoded.acknowledged_input) > 0:
		observed_ack = true
		print("SSF_BOT_ACK sequence=%d" % decoded.acknowledged_input)
	for state_value in decoded.states:
		var state := state_value as Dictionary
		if not observed_movement and (state.velocity as Vector2).length() > 1.0:
			observed_movement = true
			print("SSF_BOT_MOVEMENT peer_id=%d" % state.peer_id)
		if not observed_aim and absf(float(state.aim_angle)) > 0.1:
			observed_aim = true
			print("SSF_BOT_AIM peer_id=%d" % state.peer_id)
		if not observed_shield and bool(state.shielding):
			observed_shield = true
			print("SSF_BOT_SHIELD peer_id=%d" % state.peer_id)


func _on_projectile_batch(decoded: Dictionary) -> void:
	if not (decoded.spawned as Array).is_empty():
		print("SSF_BOT_PROJECTILES spawned=%d removed=%d" % [(decoded.spawned as Array).size(), (decoded.removed as Array).size()])


func _on_projectile_correction(decoded: Dictionary) -> void:
	if not observed_correction:
		observed_correction = true
		print("SSF_BOT_CORRECTION active=%d" % (decoded.spawned as Array).size())


func _on_rejected(reason: StringName, message: String) -> void:
	printerr("SSF_BOT_REJECTED reason=%s message=%s" % [reason, message])
	get_tree().quit(1)


func _on_connection_lost(message: String) -> void:
	print("SSF_BOT_DISCONNECTED message=%s" % message)
	if welcomed:
		get_tree().quit(0)


func _exit_tree() -> void:
	if bridge != null:
		bridge.stop()
