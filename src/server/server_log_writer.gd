extends RefCounted

# Console/file sinks may stall independently of gameplay. Only strings cross
# this worker boundary; transport, world state and Nodes stay on the main thread.
const DEFAULT_MAX_QUEUED_CHARACTERS: int = 262_144

var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _queue: PackedStringArray = []
var _queued_characters: int = 0
var _max_queued_characters: int
var _dropped_batches: int = 0
var _total_dropped_batches: int = 0
var _stopping: bool = false


func _init(max_queued_characters: int = DEFAULT_MAX_QUEUED_CHARACTERS) -> void:
	_max_queued_characters = maxi(max_queued_characters, 1)


func start() -> Error:
	return _thread.start(_run)


func enqueue(text: String) -> void:
	_mutex.lock()
	if not _stopping:
		if _queued_characters + text.length() <= _max_queued_characters:
			_queue.append(text)
			_queued_characters += text.length()
		else:
			_dropped_batches += 1
			_total_dropped_batches += 1
	_mutex.unlock()
	_wake.post()


func stop() -> void:
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	if _thread.is_started():
		_thread.wait_to_finish()


func status() -> Dictionary:
	_mutex.lock()
	var result := {"queued_batches": _queue.size(), "queued_characters": _queued_characters, "dropped_batches": _total_dropped_batches}
	_mutex.unlock()
	return result


func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var batch := _queue
		_queue = PackedStringArray()
		_queued_characters = 0
		var dropped := _dropped_batches
		_dropped_batches = 0
		var stopping := _stopping
		_mutex.unlock()
		# Never hold the producer mutex while touching an output sink.
		if not batch.is_empty():
			_write_output("\n".join(batch))
		if dropped > 0:
			_write_output(JSON.stringify({"event": "server_log_overflow", "dropped_batches": dropped}))
		if stopping:
			return


func _write_output(text: String) -> void:
	print(text)
