class_name ServerTickMetrics
extends RefCounted

## Dedicated-server tick timing. NetworkBridge records one sample per physics
## callback and, every INTERVAL_USEC, closes a window into the structured
## `simulation_metrics` log entry. Pure bookkeeping: no node, world or
## transport access, so it is tested directly.

const INTERVAL_USEC: int = 10_000_000

var server_started_usec: int = 0
var window_started_usec: int = 0
## The most recently closed window, as logged.
var latest: Dictionary = {}
var window: int = 0

var _last_tick_start_usec: int = 0
var _max_tick_gap_usec: int = 0
var _total_usec: int = 0
var _max_usec: int = 0
var _samples: int = 0
var _sample_usec: Array[int] = []
var _active_sample_usec: Array[int] = []
var _over_budget_ticks: int = 0
var _phase_totals_usec: Dictionary = {"simulation": 0, "coordination": 0, "replication": 0, "logging": 0}
var _max_logging_usec: int = 0


## Begins a fresh server run: uptime restarts and no window has been logged.
func start(now_usec: int) -> void:
	server_started_usec = now_usec
	_last_tick_start_usec = 0
	latest = {}
	window = 0
	reset_window(now_usec)


## Records one server callback. The phase boundaries are microsecond
## timestamps: after world/NPC simulation, after match coordination, after
## replication, and at the end (after log flushing). `active` is whether
## controls were enabled, i.e. combat was running.
func record_tick(start_usec: int, simulation_done_usec: int, coordination_done_usec: int, replication_done_usec: int, end_usec: int, active: bool) -> void:
	if _last_tick_start_usec > 0:
		_max_tick_gap_usec = maxi(_max_tick_gap_usec, start_usec - _last_tick_start_usec)
	_last_tick_start_usec = start_usec
	var duration_usec := end_usec - start_usec
	_phase_totals_usec.simulation += simulation_done_usec - start_usec
	_phase_totals_usec.coordination += coordination_done_usec - simulation_done_usec
	_phase_totals_usec.replication += replication_done_usec - coordination_done_usec
	var logging_usec := end_usec - replication_done_usec
	_phase_totals_usec.logging += logging_usec
	_max_logging_usec = maxi(_max_logging_usec, logging_usec)
	if active:
		_active_sample_usec.append(duration_usec)
	_total_usec += duration_usec
	_max_usec = maxi(_max_usec, duration_usec)
	_samples += 1
	_sample_usec.append(duration_usec)
	if duration_usec > int(1_000_000.0 / GameConstants.PHYSICS_TICKS_PER_SECOND):
		_over_budget_ticks += 1


## Windows rotate on wall time, not match time, so idle and paused servers
## still report liveness and sample storage stays bounded.
func is_due(now_usec: int) -> bool:
	return now_usec - window_started_usec >= INTERVAL_USEC


## Callbacks recorded in the open window.
func sample_count() -> int:
	return _samples


func uptime_seconds(now_usec: int) -> float:
	return float(now_usec - server_started_usec) / 1_000_000.0


func window_age_seconds(now_usec: int) -> float:
	return float(now_usec - window_started_usec) / 1_000_000.0


## Closes the current window into `latest` and returns it. `context` carries the
## fields only the bridge can observe (lobby, world, logging and replication
## counters). The caller logs the result and then calls reset_window().
func close_window(now_usec: int, context: Dictionary) -> Dictionary:
	var elapsed_seconds := maxf(float(now_usec - window_started_usec) / 1_000_000.0, 0.000001)
	var mean_usec := float(_total_usec) / _samples if _samples > 0 else 0.0
	var divisor := maxi(_samples, 1)
	window += 1
	var outbound_bytes := int(context.get("outbound_bytes", 0))
	latest = {
		"window": window,
		"phase_work": context.get("phase_work", {}),
		"window_seconds": elapsed_seconds,
		"physics_samples": _samples,
		"physics_ticks_per_second": float(_samples) / elapsed_seconds,
		"max_physics_gap_usec": _max_tick_gap_usec,
		"match_active": context.get("match_active", false),
		"simulation_paused": context.get("simulation_paused", false),
		"server_tick": context.get("server_tick", 0),
		"connected_peers": context.get("connected_peers", 0),
		"npc_pilots": context.get("npc_pilots", 0),
		"participant_records": context.get("participant_records", 0),
		"active_ships": context.get("active_ships", 0),
		"active_projectiles": context.get("active_projectiles", 0),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"mean_simulation_usec": mean_usec,
		"p95_simulation_usec": percentile_usec(_sample_usec, 0.95),
		"p99_simulation_usec": percentile_usec(_sample_usec, 0.99),
		"active_samples": _active_sample_usec.size(),
		"active_p95_usec": percentile_usec(_active_sample_usec, 0.95),
		"active_p99_usec": percentile_usec(_active_sample_usec, 0.99),
		"mean_world_and_npc_usec": float(_phase_totals_usec.simulation) / divisor,
		"mean_coordination_usec": float(_phase_totals_usec.coordination) / divisor,
		"mean_replication_usec": float(_phase_totals_usec.replication) / divisor,
		"mean_logging_usec": float(_phase_totals_usec.logging) / divisor,
		"max_logging_usec": _max_logging_usec,
		"log_queued_batches": context.get("log_queued_batches", 0),
		"log_dropped_batches": context.get("log_dropped_batches", 0),
		"projectile_budget_evictions": context.get("projectile_budget_evictions", 0),
		"max_simulation_usec": _max_usec,
		"over_budget_ticks": _over_budget_ticks,
		"over_budget_percent": float(_over_budget_ticks) / divisor * 100.0,
		"outbound_bytes": outbound_bytes,
		"outbound_payload": context.get("outbound_payload", {}),
		"outbound_bytes_per_second": float(outbound_bytes) / elapsed_seconds,
	}
	return latest


func reset_window(now_usec: int) -> void:
	window_started_usec = now_usec
	_max_tick_gap_usec = 0
	_total_usec = 0
	_max_usec = 0
	_samples = 0
	_sample_usec.clear()
	_over_budget_ticks = 0
	_phase_totals_usec = {"simulation": 0, "coordination": 0, "replication": 0, "logging": 0}
	_max_logging_usec = 0
	_active_sample_usec.clear()


static func percentile_usec(samples: Array, percentile: float) -> int:
	if samples.is_empty():
		return 0
	var ordered := samples.duplicate()
	ordered.sort()
	var index := clampi(ceili(clampf(percentile, 0.0, 1.0) * ordered.size()) - 1, 0, ordered.size() - 1)
	return ordered[index]
