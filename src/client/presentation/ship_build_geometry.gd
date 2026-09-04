extends RefCounted

## Up to three small physical modules, all inside the existing hull envelope.
## Equipment never changes the hit circle, shield arc or allegiance marker.
static func families(stats: CombatStats) -> Array[StringName]:
	var result: Array[StringName] = []
	if stats.beam_weapon:
		result.append(&"beam")
	elif stats.projectile_count > 1:
		result.append(&"spread")
	elif stats.projectile_damage > 30.0 or stats.projectile_speed > 1100.0:
		result.append(&"cannon")
	if stats.shield_ram_damage > 0.0 or stats.shield_capacity > 125.0 or stats.rebound_shield_enabled:
		result.append(&"shield")
	if stats.afterburner_enabled or stats.breakaway_thrusters_enabled or stats.max_speed > 530.0:
		result.append(&"drive")
	elif stats.mine_layer_enabled or stats.missile_launcher_enabled:
		result.append(&"ordnance")
	elif stats.auto_repair_enabled:
		result.append(&"repair")
	return result


static func polygons(family: StringName) -> Array[PackedVector2Array]:
	match family:
		&"beam":
			return [PackedVector2Array([Vector2(8,-3),Vector2(26,-3),Vector2(26,3),Vector2(8,3)])]
		&"spread":
			return [PackedVector2Array([Vector2(10,-5),Vector2(17,-11),Vector2(20,-8),Vector2(13,-2)]), PackedVector2Array([Vector2(10,5),Vector2(17,11),Vector2(20,8),Vector2(13,2)])]
		&"cannon":
			return [PackedVector2Array([Vector2(8,-5),Vector2(23,-5),Vector2(27,0),Vector2(23,5),Vector2(8,5)])]
		&"shield":
			return [PackedVector2Array([Vector2(5,-12),Vector2(11,-16),Vector2(-9,-22),Vector2(-15,-17)]), PackedVector2Array([Vector2(5,12),Vector2(11,16),Vector2(-9,22),Vector2(-15,17)])]
		&"drive":
			return [PackedVector2Array([Vector2(-8,-12),Vector2(-21,-17),Vector2(-24,-12),Vector2(-12,-7)]), PackedVector2Array([Vector2(-8,12),Vector2(-21,17),Vector2(-24,12),Vector2(-12,7)])]
		&"ordnance":
			return [PackedVector2Array([Vector2(-5,-13),Vector2(-16,-20),Vector2(-20,-16),Vector2(-9,-9)]), PackedVector2Array([Vector2(-5,13),Vector2(-16,20),Vector2(-20,16),Vector2(-9,9)])]
		&"repair":
			return [PackedVector2Array([Vector2(-12,-5),Vector2(-20,-5),Vector2(-20,5),Vector2(-12,5)])]
	return []
