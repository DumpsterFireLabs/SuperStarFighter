extends Node

## The main menu's credits screen. Emits `closed` when the player backs out so
## the client can return focus to the menu.

signal closed

const DesignTokensScript = preload("res://src/client/ui/design_tokens.gd")
const REPOSITORY_URL := "https://github.com/DumpsterFireLabs/SuperStarFighter"

var panel: Control


func is_open() -> bool:
	return panel != null and panel.visible


func create_ui(canvas: CanvasLayer, theme: Theme, panel_style: StyleBox) -> void:
	panel = Control.new()
	panel.name = "CreditsScreen"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	canvas.add_child(panel)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color("02040d", 0.92)
	panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(960.0, 610.0)
	card.theme = theme
	card.add_theme_stylebox_override("panel", panel_style)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	var kicker := Label.new()
	kicker.text = "✦  DUMPSTER FIRE LABS PRESENTS  ✦"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.theme_type_variation = &"Kicker"
	content.add_child(kicker)
	var title := Label.new()
	title.text = "THANKS FOR PLAYING!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.theme_type_variation = &"ScreenTitle"
	content.add_child(title)
	var thank_you := Label.new()
	thank_you.text = "To everyone who stepped into the arena—thank you for giving the game a shot.\nI set out to make the kind of game I’d have a blast playing with friends, whether at a LAN party or online.\nI hope you had as much fun playing—and testing—it as I did making it!"
	thank_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	thank_you.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thank_you.custom_minimum_size = Vector2(900.0, 0.0)
	thank_you.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	thank_you.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	content.add_child(thank_you)
	_add_credit_block(content, "CREATED BY", "Graphite  ·  jbohack  ·  Champ")
	_add_credit_block(content, "TESTERS", "Equip  ·  KingRat  ·  DoomGuy  ·  Adam  ·  WhackyJacky  ·  Hipu  ·  Krusty Dave  ·  NoPE  ·  OSINTI4L  ·  TurboDoink  ·  AK-REX  ·  Dakka  ·  Gremlin  ·  Trash Panda  ·  SkonSolo")
	_add_credit_block(content, "SPECIAL THANKS", "ChatGPT  ·  Claude")
	var repo_center := CenterContainer.new()
	content.add_child(repo_center)
	var repo_link := LinkButton.new()
	repo_link.text = "github.com/DumpsterFireLabs/SuperStarFighter"
	repo_link.uri = REPOSITORY_URL
	repo_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	repo_link.add_theme_font_size_override("font_size", DesignTokensScript.TEXT_BODY_SIZE)
	repo_link.add_theme_color_override("font_color", DesignTokensScript.BRAND_CYAN)
	repo_link.add_theme_color_override("font_hover_color", DesignTokensScript.FOCUS)
	repo_link.add_theme_color_override("font_focus_color", DesignTokensScript.FOCUS)
	# ON_HOVER only reacts to the mouse, so keyboard and controller focus underline explicitly.
	repo_link.focus_entered.connect(func() -> void: repo_link.underline = LinkButton.UNDERLINE_MODE_ALWAYS)
	repo_link.focus_exited.connect(func() -> void: repo_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER)
	repo_center.add_child(repo_link)
	var back_center := CenterContainer.new()
	content.add_child(back_center)
	var back_button := Button.new()
	back_button.text = "BACK TO MAIN MENU"
	back_button.theme_type_variation = &"PrimaryButton"
	back_button.custom_minimum_size = Vector2(300.0, 52.0)
	back_button.pressed.connect(close)
	back_center.add_child(back_button)


func open() -> void:
	panel.visible = true
	for child in panel.find_children("*", "Button", true, false):
		(child as Button).grab_focus()
		break


func close() -> void:
	panel.visible = false
	closed.emit()


func _add_credit_block(parent: VBoxContainer, role: String, names: String) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	var role_label := Label.new()
	role_label.text = role
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.theme_type_variation = &"Kicker"
	block.add_child(role_label)
	var names_label := Label.new()
	names_label.text = names
	names_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names_label.custom_minimum_size = Vector2(650.0, 0.0)
	names_label.add_theme_font_size_override("font_size", 24)
	names_label.add_theme_color_override("font_color", DesignTokensScript.TEXT_PRIMARY)
	block.add_child(names_label)
