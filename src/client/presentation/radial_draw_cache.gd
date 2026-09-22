extends RefCounted

## Two shared immutable masks, prepared once before combat drawing.
static var disc: ImageTexture
static var mine_ring: ImageTexture

static func prepare() -> void:
	if disc != null: return
	disc = _radial_mask(128, 0.0)
	mine_ring = _radial_mask(144, GameConstants.MINE_TRIGGER_RADIUS - 1.0)

static func _radial_mask(size: int, inner_radius: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * size * 0.5
	var outer_radius := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var distance := (Vector2(x + 0.5, y + 0.5) - center).length()
			var alpha := clampf(outer_radius - distance + 0.5, 0.0, 1.0)
			if inner_radius > 0.0:
				alpha *= clampf(distance - inner_radius + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
