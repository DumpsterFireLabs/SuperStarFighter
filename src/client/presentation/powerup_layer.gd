class_name PowerupLayer
extends Node2D

var powerups: Dictionary = {}
var catalog := CardCatalog.create_default()
var elapsed: float = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func set_powerups(items: Array) -> void:
	powerups.clear()
	for item_value in items:
		var item := item_value as Dictionary
		var powerup_id := int(item.get("powerup_id", 0))
		if powerup_id > 0:
			powerups[powerup_id] = item.duplicate(true)
	queue_redraw()


func add_powerup(item: Dictionary) -> void:
	var powerup_id := int(item.get("powerup_id", 0))
	if powerup_id <= 0:
		return
	powerups[powerup_id] = item.duplicate(true)
	queue_redraw()


func remove_powerup(powerup_id: int) -> void:
	powerups.erase(powerup_id)
	queue_redraw()


func clear_powerups() -> void:
	powerups.clear()
	queue_redraw()


func _draw() -> void:
	var pulse := 0.82 + sin(elapsed * 4.5) * 0.18
	var ids := powerups.keys()
	ids.sort()
	for powerup_id in ids:
		var powerup := powerups[powerup_id] as Dictionary
		var position := powerup.get("position", Vector2.ZERO) as Vector2
		var card := catalog.get_card(StringName(powerup.get("card_id", &"")))
		var rarity_color := card.rarity_color() if card != null else Color("42e8ff")
		draw_circle(position, 34.0 + pulse * 5.0, Color(rarity_color, 0.08 + pulse * 0.08))
		draw_arc(position, 31.0 + pulse * 4.0, 0.0, TAU, 28, Color(rarity_color, 0.7), 3.0)
		var points := PackedVector2Array([
			position + Vector2(0.0, -23.0),
			position + Vector2(20.0, 0.0),
			position + Vector2(0.0, 23.0),
			position + Vector2(-20.0, 0.0),
		])
		draw_colored_polygon(points, Color(rarity_color.darkened(0.65), 0.94))
		draw_polyline(points + PackedVector2Array([points[0]]), rarity_color.lightened(pulse * 0.12), 4.0)
		draw_string(ThemeDB.fallback_font, position + Vector2(-16.0, 7.0), "✦", HORIZONTAL_ALIGNMENT_CENTER, 32.0, 20, Color("f8fcff"))
		var label := card.display_name.to_upper() if card != null else "CARD POWERUP"
		draw_string(ThemeDB.fallback_font, position + Vector2(-90.0, -43.0), label, HORIZONTAL_ALIGNMENT_CENTER, 180.0, 14, rarity_color.lightened(0.18))
		var tier := "%s PICKUP" % (card.rarity_name().to_upper() if card != null else "RARE+")
		draw_string(ThemeDB.fallback_font, position + Vector2(-70.0, 50.0), tier, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 12, Color("dcecff"))
