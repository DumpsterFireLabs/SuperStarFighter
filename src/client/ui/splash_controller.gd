extends Node

## Owns the two-stage launch splash: the studio card, then the game title.
## Any start input advances one stage; each stage also advances on a timer.
## Emits `finished` once the splash is gone so the client can focus its menu.

signal finished(immediate: bool)

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const DUMPSTER_FIRE_LABS_TEXTURE: Texture2D = preload("res://assets/ui/dumpster_fire_labs.png")
const STUDIO_AUTO_ADVANCE_SECONDS: float = 4.0
const GAME_AUTO_ADVANCE_SECONDS: float = 10.0

var screen: Control
var studio_splash: Control
var game_splash: Control
var neon_backdrop: Control
var auto_timer: Timer
## 0 while the studio card shows, 1 once the game title is reached.
var stage: int = 0
var transitioning: bool = false
var dismissed: bool = false


func is_showing() -> bool:
	return screen != null and screen.visible


## Builds the splash on its own canvas layer and starts the studio card.
func create_ui(register_interface_scope: Callable) -> void:
	var splash_canvas := CanvasLayer.new()
	splash_canvas.layer = 40
	splash_canvas.name = "SplashUI"
	add_child(splash_canvas)
	register_interface_scope.call(splash_canvas)
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_canvas.add_child(screen)
	var studio_backdrop := ColorRect.new()
	studio_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_backdrop.color = Color("1d3a3a")
	screen.add_child(studio_backdrop)
	neon_backdrop = NeonBackdrop.new()
	neon_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	neon_backdrop.visible = false
	screen.add_child(neon_backdrop)
	studio_splash = Control.new()
	studio_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(studio_splash)
	var studio_center := CenterContainer.new()
	studio_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	studio_splash.add_child(studio_center)
	var studio_content := VBoxContainer.new()
	studio_content.alignment = BoxContainer.ALIGNMENT_CENTER
	studio_content.add_theme_constant_override("separation", 12)
	studio_center.add_child(studio_content)
	var studio_logo := TextureRect.new()
	studio_logo.name = "DumpsterFireLabsLogo"
	studio_logo.texture = DUMPSTER_FIRE_LABS_TEXTURE
	studio_logo.custom_minimum_size = Vector2(470.0, 470.0)
	studio_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	studio_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	studio_content.add_child(studio_logo)
	var quote := Label.new()
	quote.name = "StudioQuote"
	quote.text = "“Now with 1000% more slop!”"
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.add_theme_font_size_override("font_size", 30)
	quote.add_theme_color_override("font_color", Color("ffe7a8"))
	studio_content.add_child(quote)
	var studio_skip := Label.new()
	studio_skip.text = "PRESS ANY INPUT TO CONTINUE"
	studio_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	studio_skip.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	studio_skip.add_theme_color_override("font_color", Color("7ee0bd"))
	studio_content.add_child(studio_skip)
	game_splash = Control.new()
	game_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_splash.visible = false
	screen.add_child(game_splash)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_splash.add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(content)
	var logo := SplashLogo.new()
	logo.custom_minimum_size = Vector2(520.0, 300.0)
	content.add_child(logo)
	var title := Label.new()
	title.text = "SUPER STAR FIGHTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", DesignTokensScript.BRAND_CYAN)
	content.add_child(title)
	var flare := Label.new()
	flare.text = "✦  POWER UP · OUTGUN · OUTLAST  ✦"
	flare.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flare.add_theme_font_size_override("font_size", 28)
	flare.add_theme_color_override("font_color", DesignTokensScript.BRAND_MAGENTA)
	content.add_child(flare)
	var skip := Label.new()
	skip.text = "PRESS ANY INPUT TO START"
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	skip.add_theme_color_override("font_color", DesignTokensScript.BRAND_CYAN)
	content.add_child(skip)
	studio_content.modulate = Color(1, 1, 1, 0)
	studio_content.scale = Vector2(0.88, 0.88)
	studio_content.pivot_offset = Vector2(235.0, 270.0)
	var intro := create_tween().set_parallel(true)
	intro.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(studio_content, "modulate", Color.WHITE, 0.8)
	intro.tween_property(studio_content, "scale", Vector2.ONE, 1.05)
	auto_timer = Timer.new()
	auto_timer.one_shot = true
	auto_timer.timeout.connect(dismiss)
	screen.add_child(auto_timer)
	auto_timer.start(STUDIO_AUTO_ADVANCE_SECONDS)


## Advances one stage, or with `immediate` hides the splash at once.
func dismiss(immediate: bool = false) -> void:
	if dismissed or screen == null or transitioning:
		return
	if immediate:
		dismissed = true
		if auto_timer != null:
			auto_timer.stop()
		screen.visible = false
		finished.emit(true)
		return
	if stage == 0:
		_transition_to_game_splash()
		return
	dismissed = true
	if auto_timer != null:
		auto_timer.stop()
	var fade := create_tween()
	fade.tween_property(screen, "modulate", Color(1, 1, 1, 0), 0.35)
	fade.finished.connect(_finish_dismissal)


## Shows the game title stage immediately, as captures do.
func show_game_splash() -> void:
	if auto_timer != null:
		auto_timer.stop()
	stage = 1
	studio_splash.visible = false
	neon_backdrop.visible = true
	game_splash.visible = true
	game_splash.modulate = Color.WHITE


func _transition_to_game_splash() -> void:
	stage = 1
	transitioning = true
	if auto_timer != null:
		auto_timer.stop()
	var fade_out := create_tween()
	fade_out.tween_property(studio_splash, "modulate", Color(1, 1, 1, 0), 0.3)
	fade_out.finished.connect(finish_studio_splash)


func finish_studio_splash() -> void:
	if dismissed:
		return
	studio_splash.visible = false
	neon_backdrop.visible = true
	game_splash.visible = true
	game_splash.modulate = Color(1, 1, 1, 0)
	var intro := create_tween().set_parallel(true)
	intro.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(game_splash, "modulate", Color.WHITE, 0.6)
	intro.finished.connect(finish_game_splash_intro)


func finish_game_splash_intro() -> void:
	if dismissed:
		return
	transitioning = false
	if auto_timer != null:
		auto_timer.start(GAME_AUTO_ADVANCE_SECONDS)


func _finish_dismissal() -> void:
	screen.visible = false
	finished.emit(false)
