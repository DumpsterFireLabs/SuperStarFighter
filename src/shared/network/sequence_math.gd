class_name SequenceMath
extends RefCounted

const UINT32_MASK: int = 0xffffffff
const HALF_RANGE: int = 0x80000000


static func normalize(value: int) -> int:
	return value & UINT32_MASK


static func is_newer(candidate: int, reference: int) -> bool:
	var difference := (candidate - reference) & UINT32_MASK
	return difference != 0 and difference < HALF_RANGE


static func is_newer_or_equal(candidate: int, reference: int) -> bool:
	return normalize(candidate) == normalize(reference) or is_newer(candidate, reference)


static func increment(value: int) -> int:
	return (value + 1) & UINT32_MASK
