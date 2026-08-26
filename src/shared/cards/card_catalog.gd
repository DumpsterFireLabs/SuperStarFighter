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
	"res://data/cards/lightweight_frame.tres",
	"res://data/cards/vectored_nozzles.tres",
	"res://data/cards/combat_gyros.tres",
	"res://data/cards/scar_tissue.tres",
	"res://data/cards/sprint_reactor.tres",
	"res://data/cards/braking_foils.tres",
	"res://data/cards/shielded_drive.tres",
	"res://data/cards/damage_control.tres",
	"res://data/cards/adaptive_chassis.tres",
	"res://data/cards/repair_gel.tres",
	"res://data/cards/pursuit_engine.tres",
	"res://data/cards/juggernaut_frame.tres",
	"res://data/cards/comet_drive.tres",
	"res://data/cards/recursive_nanites.tres",
	"res://data/cards/phase_brakes.tres",
	"res://data/cards/warpshell.tres",
	"res://data/cards/immortal_lattice.tres",
	"res://data/cards/lightspeed_frame.tres",
	"res://data/cards/ouroboros_hull.tres",
	"res://data/cards/transcendent_chassis.tres",
	"res://data/cards/pulse_capacitor.tres",
	"res://data/cards/low_loss_coils.tres",
	"res://data/cards/compact_deflector.tres",
	"res://data/cards/recovery_switch.tres",
	"res://data/cards/kinetic_converter.tres",
	"res://data/cards/pursuit_screen.tres",
	"res://data/cards/broadside_field.tres",
	"res://data/cards/deep_reserves.tres",
	"res://data/cards/flash_recharger.tres",
	"res://data/cards/resilient_grid.tres",
	"res://data/cards/duelist_aegis.tres",
	"res://data/cards/mobile_bulwark.tres",
	"res://data/cards/vacuum_insulation.tres",
	"res://data/cards/cascade_barrier.tres",
	"res://data/cards/second_wind.tres",
	"res://data/cards/stellar_aegis.tres",
	"res://data/cards/perpetual_field.tres",
	"res://data/cards/inviolable_front.tres",
	"res://data/cards/instant_recovery.tres",
	"res://data/cards/absolute_barrier.tres",
	"res://data/cards/long_fuse_rounds.tres",
	"res://data/cards/short_fuse_payload.tres",
	"res://data/cards/tight_bore.tres",
	"res://data/cards/drum_spring.tres",
	"res://data/cards/hot_load.tres",
	"res://data/cards/rangefinder.tres",
	"res://data/cards/impact_lens.tres",
	"res://data/cards/bank_shot.tres",
	"res://data/cards/flechette_payload.tres",
	"res://data/cards/overpressure_chamber.tres",
	"res://data/cards/sustained_barrage.tres",
	"res://data/cards/deadeye_calibration.tres",
	"res://data/cards/orbital_rounds.tres",
	"res://data/cards/chain_ricochet.tres",
	"res://data/cards/needle_storm.tres",
	"res://data/cards/annihilator_shell.tres",
	"res://data/cards/impossible_magazine.tres",
	"res://data/cards/horizon_round.tres",
	"res://data/cards/storm_of_one.tres",
	"res://data/cards/supernova_array.tres",
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


func eligible_ids(_build: Dictionary) -> Array[StringName]:
	# Builds never exhaust a card. Offers remain unique within a single draw,
	# while the same card may be acquired again in every later draft.
	return all_ids()


func validate_default_catalog() -> PackedStringArray:
	var errors := load_errors.duplicate()
	if size() != DEFAULT_CARD_PATHS.size():
		errors.append("Default catalog must contain exactly %d cards; found %d." % [DEFAULT_CARD_PATHS.size(), size()])
	var mechanical_signatures: Dictionary = {}
	var mechanical_shapes: Dictionary = {}
	for card_id in all_ids():
		var card := get_card(card_id)
		errors.append_array(StatSystem.validate_card(card))
		var signature := mechanical_signature(card)
		if mechanical_signatures.has(signature):
			errors.append("Cards %s and %s have identical mechanics." % [mechanical_signatures[signature], card_id])
		else:
			mechanical_signatures[signature] = card_id
		var shape := mechanical_shape_signature(card)
		if mechanical_shapes.has(shape):
			errors.append("Cards %s and %s modify the same stats in the same directions." % [mechanical_shapes[shape], card_id])
		else:
			mechanical_shapes[shape] = card_id
	return errors


static func mechanical_signature(card: CardDefinition) -> String:
	if card == null:
		return "null"
	var parts := PackedStringArray()
	parts.append_array(_modifier_signature("add", card.additive_modifiers))
	parts.append_array(_modifier_signature("mul", card.multiplicative_modifiers))
	parts.append_array(_modifier_signature("int", card.integer_modifiers))
	parts.append("special:%s" % card.special_behavior_id)
	return "|".join(parts)


static func mechanical_shape_signature(card: CardDefinition) -> String:
	if card == null:
		return "null"
	var parts := PackedStringArray()
	parts.append_array(_modifier_shape_signature("add", card.additive_modifiers, 0.0))
	parts.append_array(_modifier_shape_signature("mul", card.multiplicative_modifiers, 1.0))
	parts.append_array(_modifier_shape_signature("int", card.integer_modifiers, 0.0))
	parts.append("special:%s" % card.special_behavior_id)
	return "|".join(parts)


static func _modifier_signature(prefix: String, modifiers: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var property_names := modifiers.keys()
	property_names.sort()
	for property_value in property_names:
		var property_name := String(property_value)
		result.append("%s:%s=%s" % [prefix, property_name, str(modifiers[property_value])])
	return result


static func _modifier_shape_signature(
	prefix: String,
	modifiers: Dictionary,
	neutral_value: float
) -> PackedStringArray:
	var result := PackedStringArray()
	var property_names := modifiers.keys()
	property_names.sort()
	for property_value in property_names:
		var value := float(modifiers[property_value])
		var direction := "up" if value > neutral_value else ("down" if value < neutral_value else "flat")
		result.append("%s:%s=%s" % [prefix, String(property_value), direction])
	return result
