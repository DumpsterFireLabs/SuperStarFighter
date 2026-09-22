extends SceneTree

## Repeated teardown after drafts, active combat, replication and audio preparation.
## Measures Godot tracked memory/object retention; OS RSS is covered by verify-soak.
const Preparation = preload("res://src/client/presentation/weapon_audio_preparation.gd")
var cycles := 80

func _initialize() -> void:
	_run.call_deferred()

func _cycle(index: int) -> void:
	var config := MatchConfig.new()
	config.draft_duration_seconds = 0.05
	config.countdown_duration_seconds = 0.05
	var lobby := ServerLobby.new(config)
	var world := AuthoritativeWorld.new()
	for peer in range(1, 33):
		lobby.admit(peer, "Pilot%d" % peer)
		world.add_peer(peer)
	var coordinator := AuthoritativeMatchCoordinator.new(lobby, world, index)
	coordinator.incremental_drafts = true
	coordinator.start(0)
	for tick in 40:
		world.step(1.0 / 60.0, coordinator.controls_enabled())
		coordinator.step(1.0 / 60.0)
		coordinator.drain_private_offers()
		coordinator.drain_events()
	var scheduler := NetworkReplicationScheduler.new()
	lobby.match_active = true
	for tick in 12: scheduler.replicate_tick(tick, lobby, world)
	scheduler.clear()
	var preparation := Preparation.new()
	var profile = WeaponSoundProfile.from_stats(CombatStats.create_base())
	preparation.request(profile, index % 3, null, false)
	preparation.poll()
	preparation.close()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cycles="): cycles = clampi(int(argument.get_slice("=", 1)), 20, 2000)
	var rows: Array[Dictionary] = []
	for index in cycles + 10:
		_cycle(index)
		await process_frame
		if index >= 10:
			rows.append({"cycle": index - 10, "bytes": OS.get_static_memory_usage(), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT))})
	var growth := int(rows.back().bytes) - int(rows.front().bytes)
	var objects := int(rows.back().objects) - int(rows.front().objects)
	# Samples themselves consume bounded memory; a retained match per cycle is much larger.
	var valid := growth < 4 * 1024 * 1024 and objects < 64
	print("SSF_ARCHITECTURE_MEMORY=" + JSON.stringify({"valid": valid, "cycles": cycles, "memory_growth_bytes": growth, "object_growth": objects, "samples": rows, "scope": "Godot tracked memory after teardown; ten warmup cycles; excludes driver/OS RSS"}))
	quit(0 if valid else 1)
