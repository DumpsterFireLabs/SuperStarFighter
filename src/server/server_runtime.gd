extends RefCounted

## Shared authority composition. The caller owns node placement and MultiplayerAPI.
const LogWriter = preload("res://src/server/server_log_writer.gd")

var bridge: NetworkBridge
var log_writer: RefCounted


func attach(parent: Node, writer: RefCounted = null) -> NetworkBridge:
	assert(bridge == null, "Stop the previous server runtime before attaching again.")
	bridge = NetworkBridge.new()
	log_writer = writer if writer != null else LogWriter.new()
	if log_writer.start() == OK:
		bridge.log_output = log_writer.enqueue
		bridge.log_status = log_writer.status
	else:
		push_warning("Server log worker unavailable; using synchronous output.")
		log_writer = null
	bridge.name = "NetworkBridge"
	parent.add_child(bridge)
	return bridge


func stop() -> void:
	if is_instance_valid(bridge):
		bridge.stop()
		bridge.log_output = Callable()
		bridge.log_status = Callable()
	if log_writer != null:
		log_writer.stop()
	log_writer = null
	bridge = null
