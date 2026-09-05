extends Node

## Owns the embedded authority and its isolated MultiplayerAPI registration.
## RPC paths under the registration stay Main/NetworkBridge, like a dedicated host.
var runtime_root: Node
var server_bridge: NetworkBridge
var server_multiplayer: MultiplayerAPI
var last_error: String = ""
var _registered_tree: SceneTree
var _registered_path: NodePath


func start(configuration: Dictionary) -> Error:
	stop()
	last_error = ""
	runtime_root = Node.new()
	runtime_root.name = "HostedServerRuntime"
	add_child(runtime_root)
	server_multiplayer = MultiplayerAPI.create_default_interface()
	_registered_tree = get_tree()
	_registered_path = runtime_root.get_path()
	_registered_tree.set_multiplayer(server_multiplayer, _registered_path)
	var server_main := Node.new()
	server_main.name = "Main"
	runtime_root.add_child(server_main)
	server_bridge = NetworkBridge.new()
	server_bridge.name = "NetworkBridge"
	server_main.add_child(server_bridge)
	var error := server_bridge.start_server(configuration)
	if error != OK:
		last_error = server_bridge.last_error
		stop()
	return error


func stop() -> void:
	if is_instance_valid(server_bridge):
		server_bridge.stop()
	if is_instance_valid(runtime_root):
		_registered_tree.set_multiplayer(null, _registered_path)
		runtime_root.free()
	server_bridge = null
	runtime_root = null
	server_multiplayer = null
	_registered_tree = null
	_registered_path = NodePath()


func is_hosting() -> bool:
	return is_instance_valid(server_bridge) and server_bridge.role == NetworkBridge.Role.SERVER


func _exit_tree() -> void:
	stop()
