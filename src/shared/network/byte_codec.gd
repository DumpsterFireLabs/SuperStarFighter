class_name ByteCodec
extends RefCounted


static func append_u8(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)


static func append_u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 0xff)
	bytes.append((value >> 8) & 0xff)


static func append_i16(bytes: PackedByteArray, value: int) -> void:
	append_u16(bytes, value & 0xffff)


static func append_u32(bytes: PackedByteArray, value: int) -> void:
	var normalized := value & 0xffffffff
	bytes.append(normalized & 0xff)
	bytes.append((normalized >> 8) & 0xff)
	bytes.append((normalized >> 16) & 0xff)
	bytes.append((normalized >> 24) & 0xff)


static func read_u8(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset])


static func read_u16(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8)


static func read_i16(bytes: PackedByteArray, offset: int) -> int:
	var value := read_u16(bytes, offset)
	return value - 0x10000 if value >= 0x8000 else value


static func read_u32(bytes: PackedByteArray, offset: int) -> int:
	return (
		int(bytes[offset])
		| (int(bytes[offset + 1]) << 8)
		| (int(bytes[offset + 2]) << 16)
		| (int(bytes[offset + 3]) << 24)
	) & 0xffffffff
