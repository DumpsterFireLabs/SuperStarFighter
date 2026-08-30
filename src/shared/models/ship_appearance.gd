class_name ShipAppearance
extends RefCounted

const SOLID: StringName = &"solid"
const ZEBRA: StringName = &"zebra"
const LEOPARD: StringName = &"leopard"
const CHECKERBOARD: StringName = &"checkerboard"
const RACING: StringName = &"racing"
const CHEVRON: StringName = &"chevron"

const PATTERNS: Array[StringName] = [SOLID, ZEBRA, LEOPARD, CHECKERBOARD, RACING, CHEVRON]


static func is_valid_pattern(value: StringName) -> bool:
	return PATTERNS.has(value)


static func normalized_pattern(value: String) -> StringName:
	var normalized := StringName(value.strip_edges().to_lower())
	return normalized if is_valid_pattern(normalized) else &""


static func display_name(pattern: StringName) -> String:
	match pattern:
		ZEBRA: return "Zebra Stripes"
		LEOPARD: return "Leopard Spots"
		CHECKERBOARD: return "Checkerboard"
		RACING: return "Racing Stripes"
		CHEVRON: return "Chevrons"
		_: return "Solid"


static func swatch_symbol(pattern: StringName) -> String:
	match pattern:
		ZEBRA: return "≋"
		LEOPARD: return "••"
		CHECKERBOARD: return "▦"
		RACING: return "Ⅱ"
		CHEVRON: return "≫"
		_: return ""
