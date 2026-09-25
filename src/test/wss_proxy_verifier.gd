extends SceneTree

## Real wss:// client through a TLS-terminating reverse proxy (tools/verify-wss-proxy.py)
## to a --behind-proxy server bound to loopback, as with a Cloudflare Tunnel.
var server: NetworkBridge
var client: NetworkBridge
var intruder: NetworkBridge
var snapshots: int = 0
var rejection: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _runtime(label: String) -> NetworkBridge:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var main := Node.new()
	main.name = "Main"
	branch.add_child(main)
	var bridge := NetworkBridge.new()
	bridge.name = "NetworkBridge"
	main.add_child(bridge)
	return bridge


func _run() -> void:
	var server_port := 17990
	var proxy_port := 17991
	var cert_dir := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--server-port="): server_port = int(argument.get_slice("=", 1))
		if argument.begins_with("--proxy-port="): proxy_port = int(argument.get_slice("=", 1))
		if argument.begins_with("--cert-dir="): cert_dir = argument.get_slice("=", 1)
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var certificate := crypto.generate_self_signed_certificate(key, "CN=localhost,O=SSF Proxy Fixture,C=US")
	if key.save(cert_dir.path_join("key.pem")) != OK or certificate.save(cert_dir.path_join("cert.pem")) != OK:
		_fail("could not write fixture certificate")
		return
	print("SSF_WSS_CERT_READY")
	var ready_deadline := Time.get_ticks_msec() + 10000
	while not FileAccess.file_exists(cert_dir.path_join("proxy.ready")):
		if Time.get_ticks_msec() > ready_deadline:
			_fail("TLS proxy did not start")
			return
		await create_timer(0.05).timeout
	server = _runtime("Server")
	if server.start_server({"port": server_port, "max_players": 4, "ban_file": "", "lobby_password": "wss-fixture", "bind_address": "127.0.0.1", "behind_proxy": true}) != OK:
		_fail("server start: %s" % server.last_error)
		return
	var url := "wss://localhost:%d/play" % proxy_port
	intruder = _runtime("Intruder")
	intruder.session.tls_trusted_chain = certificate
	intruder.client_rejected.connect(func(reason: StringName, _message: String) -> void: rejection = String(reason))
	intruder.start_client(url, 0, "Intruder", GameConstants.PROTOCOL_VERSION, "wrong-password")
	if not await _until(func() -> bool: return not rejection.is_empty(), 10.0):
		_fail("wrong password was not rejected through the proxy")
		return
	client = _runtime("Client")
	client.session.tls_trusted_chain = certificate
	client.client_snapshot_received.connect(func(_decoded: Dictionary) -> void: snapshots += 1)
	client.client_connection_lost.connect(func(message: String) -> void: _fail("client lost connection: %s" % message))
	if client.start_client(url, 0, "TunnelPilot", GameConstants.PROTOCOL_VERSION, "wss-fixture") != OK:
		_fail("client start: %s" % client.last_error)
		return
	if not await _until(func() -> bool: return client.local_peer_id != 0, 10.0):
		_fail("wss client was not admitted")
		return
	client.send_ready_state(true)
	await _until(func() -> bool: return client.get_round_trip_time_ms() >= 0, 5.0)
	var source := server.session.peer_source(client.local_peer_id)
	var ban := server.session.operator_block_source("127.0.0.1")
	var ok: bool = rejection == String(NetworkProtocol.REJECT_INVALID_PASSWORD) and source.begins_with("proxied:") and not ban.ok and client.get_round_trip_time_ms() >= 0
	print("SSF_WSS_OK=%s" % JSON.stringify({"ok": ok, "url": url, "peer_id": client.local_peer_id, "source": source, "rtt_ms": client.get_round_trip_time_ms(), "intruder_rejection": rejection, "ban_refused": not ban.ok}))
	client.stop()
	intruder.stop()
	server.stop()
	quit(0 if ok else 1)


func _until(condition: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await create_timer(0.02).timeout
	return true


func _fail(reason: String) -> void:
	printerr("SSF_WSS_ERROR=%s" % reason)
	quit(1)
