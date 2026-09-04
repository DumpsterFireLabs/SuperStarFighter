extends SceneTree


func _initialize() -> void:
	measure.call_deferred()


func measure() -> void:
	var baseline_script := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline-script="):
			baseline_script = argument.trim_prefix("--baseline-script=")
	var before := not baseline_script.is_empty()
	var script: Script = load(baseline_script) if before else load("res://src/client/presentation/audio_director.gd")
	if script == null:
		push_error("Could not load audio memory probe target")
		quit(1)
		return
	var memory_before := OS.get_static_memory_usage()
	var started := Time.get_ticks_usec()
	var director: Node = script.new()
	root.add_child(director)
	var startup_usec := Time.get_ticks_usec() - started
	var memory_delta := OS.get_static_memory_usage() - memory_before
	var output := []
	var command := "$p=Get-Process -Id %d; @{working_set=$p.WorkingSet64;private_bytes=$p.PrivateMemorySize64}|ConvertTo-Json -Compress" % OS.get_process_id()
	var error := OS.execute("powershell.exe", ["-NoProfile", "-Command", command], output)
	var memory: Variant = JSON.parse_string(str(output[0])) if error == 0 and not output.is_empty() else null
	if not memory is Dictionary or not memory.has("working_set") or not memory.has("private_bytes"):
		push_error("OS process-memory query failed or returned malformed output")
		director.free()
		quit(1)
		return
	if not (memory.working_set is int or memory.working_set is float) or not (memory.private_bytes is int or memory.private_bytes is float) or float(memory.working_set) <= 0.0 or float(memory.private_bytes) <= 0.0:
		push_error("OS process-memory query did not return positive byte counts")
		director.free()
		quit(1)
		return
	var bytes := 0
	var streams := {}
	for player in [director.menu_player, director.win_player, director.gameplay_player]:
		if player.stream is AudioStreamWAV:
			streams[player.stream] = true
	for stream in director.gameplay_tracks:
		if stream is AudioStreamWAV:
			streams[stream] = true
	for stream in streams:
		bytes += stream.data.size()
	print("AUDIO_OS_MEMORY=" + JSON.stringify({"before": before, "startup_usec": startup_usec, "static_delta": memory_delta, "music_data_bytes": bytes, "os": memory}))
	streams.clear()
	director.free()
	quit()
