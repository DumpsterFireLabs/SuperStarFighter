class_name CardCatalog
extends RefCounted

const DEFAULT_CARD_PATHS: Array[String] = [
	"res://data/cards/auto_repair.tres",
	"res://data/cards/capacitor_bank.tres",
	"res://data/cards/efficient_field.tres",
	"res://data/cards/extended_magazine.tres",
	"res://data/cards/heavy_rounds.tres",
	"res://data/cards/overcharged_thrusters.tres",
	"res://data/cards/piercing_rounds.tres",
	"res://data/cards/quick_charge.tres",
	"res://data/cards/quick_loader.tres",
	"res://data/cards/rail_accelerant.tres",
	"res://data/cards/rapid_cycling.tres",
	"res://data/cards/reinforced_hull.tres",
	"res://data/cards/ricochet_rounds.tres",
	"res://data/cards/twin_shot.tres",
	"res://data/cards/vector_jets.tres",
	"res://data/cards/wide_emitter.tres",
	"res://data/cards/kinetic_plating.tres",
	"res://data/cards/phase_thrusters.tres",
	"res://data/cards/glass_reactor.tres",
	"res://data/cards/emergency_bulkheads.tres",
	"res://data/cards/inertial_dampers.tres",
	"res://data/cards/nanite_reservoir.tres",
	"res://data/cards/flux_reservoir.tres",
	"res://data/cards/mirror_field.tres",
	"res://data/cards/fortress_emitter.tres",
	"res://data/cards/blink_capacitor.tres",
	"res://data/cards/reactive_barrier.tres",
	"res://data/cards/omnidirectional_field.tres",
	"res://data/cards/scatter_array.tres",
	"res://data/cards/beam_emitter.tres",
	"res://data/cards/prismatic_lance.tres",
	"res://data/cards/laser_repeater.tres",
	"res://data/cards/siege_cannon.tres",
	"res://data/cards/micro_barrage.tres",
	"res://data/cards/endless_belt.tres",
	"res://data/cards/zero_point_loader.tres",
	"res://data/cards/ablative_shell.tres",
	"res://data/cards/plasma_thrusters.tres",
	"res://data/cards/gyroscopic_core.tres",
	"res://data/cards/phoenix_chassis.tres",
	"res://data/cards/starheart_reactor.tres",
	"res://data/cards/event_horizon_drive.tres",
	"res://data/cards/quantum_reconstruction.tres",
	"res://data/cards/impossible_engine.tres",
	"res://data/cards/reserve_cell.tres",
	"res://data/cards/regenerative_coils.tres",
	"res://data/cards/focused_deflector.tres",
	"res://data/cards/aegis_matrix.tres",
	"res://data/cards/solar_barrier.tres",
	"res://data/cards/chronal_shield.tres",
	"res://data/cards/infinite_refraction.tres",
	"res://data/cards/shield_siphon.tres",
	"res://data/cards/hollow_points.tres",
	"res://data/cards/cycling_servo.tres",
	"res://data/cards/accelerator_coil.tres",
	"res://data/cards/trident_array.tres",
	"res://data/cards/sunbeam_core.tres",
	"res://data/cards/causality_cannon.tres",
	"res://data/cards/singularity_lance.tres",
	"res://data/cards/reality_shredder.tres",
]

var _cards: Dictionary = {}
var load_errors := PackedStringArray()


static func create_default() -> CardCatalog:
	var catalog := CardCatalog.new()
	for path in DEFAULT_CARD_PATHS:
		var resource := load(path)
		if resource == null or not resource is CardDefinition:
			catalog.load_errors.append("Could not load CardDefinition at %s." % path)
			continue
		catalog.add_card(resource as CardDefinition)
	return catalog


func add_card(card: CardDefinition) -> bool:
	if card == null:
		load_errors.append("Cannot add a null card.")
		return false
	var validation_errors := card.validate()
	if not validation_errors.is_empty():
		load_errors.append_array(validation_errors)
		return false
	if _cards.has(card.card_id):
		load_errors.append("Duplicate card ID: %s." % card.card_id)
		return false
	_cards[card.card_id] = card
	return true


func get_card(card_id: StringName) -> CardDefinition:
	return _cards.get(card_id) as CardDefinition


func has_card(card_id: StringName) -> bool:
	return _cards.has(card_id)


func size() -> int:
	return _cards.size()


func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for card_id in _cards:
		ids.append(card_id)
	ids.sort()
	return ids


func eligible_ids(build: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id in all_ids():
		var card := get_card(card_id)
		if int(build.get(card_id, 0)) < card.max_stacks:
			result.append(card_id)
	return result


func validate_default_catalog() -> PackedStringArray:
	var errors := load_errors.duplicate()
	if size() != DEFAULT_CARD_PATHS.size():
		errors.append("Default catalog must contain exactly %d cards; found %d." % [DEFAULT_CARD_PATHS.size(), size()])
	for card_id in all_ids():
		errors.append_array(StatSystem.validate_card(get_card(card_id)))
	return errors
