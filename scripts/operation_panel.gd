extends PanelContainer
## Screen-space command console, separate from the playable map.
signal chosen(action: String)
var items: Array = []
var buttons: Dictionary = {}
var heading: Label
var stats: Label
var actions: VBoxContainer
var animation: Tween
const BASE = Color("72899b")
const HOVER = Color("889ead")
const SURFACE = Color("526c80")
const INK = Color("f4f8fb")

func surface(color: Color, inset: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.anti_aliasing = false
	style.border_color = color.darkened(0.25)
	style.set_border_width_all(2)
	style.set_content_margin_all(inset)
	return style

func _ready() -> void:
	var ui_font: Font = load("res://assets/fonts/Pixel-UI.tres")
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 24
	ui_theme.set_color("font_color", "Label", INK)
	theme = ui_theme
	add_theme_stylebox_override("panel", surface(SURFACE, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	stats = Label.new()
	stats.add_theme_font_size_override("font_size", 24)
	stats.add_theme_color_override("font_color", Color("d5e2eb"))
	column.add_child(stats)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	column.add_child(actions)
	hide()

func set_context(caption: String, count: int, distance: int, target_count: int, collection_cap: int = 0, collection_radius: int = 1, target_limit: int = -1) -> void:
	heading.text = caption
	stats.text = "能量 %s\n射程 %s" % [count, distance]
	if collection_cap > 0:
		stats.text = "储能 %s / %s\n收集 %s 格\n射程 %s" % [count, collection_cap, collection_radius, distance]
	if target_count >= 0:
		stats.text += "\n目标 %s / %s" % [target_count, target_limit] if target_limit > 0 else "\n目标 %s" % target_count

func open(entries: Array, animate: bool = true) -> void:
	items = entries.duplicate(true)
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	buttons.clear()
	for entry in items:
		var button := Button.new()
		button.custom_minimum_size.y = 56
		button.disabled = entry.get("disabled", false)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", surface(BASE, 10))
		button.add_theme_stylebox_override("hover", surface(HOVER, 10))
		button.add_theme_stylebox_override("pressed", surface(Color("425b70"), 10))
		button.add_theme_stylebox_override("disabled", surface(Color("627889"), 10))
		var focus := surface(Color(0, 0, 0, 0))
		focus.border_color = Color("e4f1fa")
		focus.set_border_width_all(2)
		button.add_theme_stylebox_override("focus", focus)
		actions.add_child(button)
		buttons[entry.action] = button
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		row.add_theme_constant_override("separation", 8)
		button.add_child(row)
		var label := Label.new()
		label.text = entry.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		if entry.has("amount"):
			var amount := Label.new()
			amount.text = entry.amount
			amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			amount.add_theme_font_override("font", load("res://assets/fonts/Pixel-Display.tres"))
			amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(amount)
		var key := Label.new()
		key.text = entry.key_label
		key.custom_minimum_size.x = 34
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 24)
		key.add_theme_color_override("font_color", Color("dae6ef"))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(key)
		if button.disabled:
			row.modulate.a = 0.42
		button.pressed.connect(func(): chosen.emit(entry.action))
		button.gui_input.connect(_gui_input)
	show()
	if animate:
		if animation != null: animation.kill()
		modulate.a = 0.0
		animation = create_tween()
		animation.tween_property(self, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		chosen.emit("close")
