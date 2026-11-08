extends Control
## Full-screen result presentation; the simulation remains owned by the host.
signal return_requested
signal quit_requested
signal reveal_changed(amount: float)
const UI_FONT = preload("res://assets/fonts/Pixel-UI.tres")
const INK = Color("17394f")
const ICE = Color("c4f1fc")
var body: Control
var heading: Label
var return_button: Button
var quit_button: Button
var animation: Tween
var reveal := 0.0:
	set(value):
		reveal = value
		reveal_changed.emit(value)
		apply_reveal()
		queue_redraw()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ui_theme := Theme.new()
	ui_theme.default_font = UI_FONT
	ui_theme.default_font_size = 24
	theme = ui_theme
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	heading = Label.new()
	heading.text = "胜利"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", Color("f1fcff"))
	heading.add_theme_color_override("font_shadow_color", Color("376c8b"))
	heading.add_theme_constant_override("shadow_offset_x", 4)
	heading.add_theme_constant_override("shadow_offset_y", 4)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(heading)
	return_button = make_button("返回首页", true)
	quit_button = make_button("退出游戏", false)
	return_button.pressed.connect(func(): return_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())
	resized.connect(update_layout)
	update_layout()
	hide()

func button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.anti_aliasing = false
	style.shadow_color = Color("0d293d")
	style.shadow_size = 0
	style.shadow_offset = Vector2(0, 4)
	return style

func make_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", button_style(ICE if primary else Color("224a63"), ICE if primary else Color("638da7")))
	button.add_theme_stylebox_override("hover", button_style(Color("f1fcff") if primary else Color("326680"), Color("f1fcff")))
	button.add_theme_stylebox_override("pressed", button_style(Color("82cce5"), Color("e9fbff")))
	button.add_theme_color_override("font_color", INK if primary else Color("e0f6fc"))
	button.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK if primary else Color.WHITE)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color.WHITE
	focus.set_border_width_all(2)
	focus.expand_margin_left = 6
	focus.expand_margin_right = 6
	focus.expand_margin_top = 6
	focus.expand_margin_bottom = 6
	focus.anti_aliasing = false
	button.add_theme_stylebox_override("focus", focus)
	body.add_child(button)
	return button

func present() -> void:
	if visible:
		return
	show()
	return_button.disabled = true
	quit_button.disabled = true
	reveal = 0.0
	animation = create_tween()
	animation.tween_property(self, "reveal", 1.0, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_callback(func():
		return_button.disabled = false
		quit_button.disabled = false
		return_button.grab_focus())

func dismiss() -> void:
	if animation != null and animation.is_valid(): animation.kill()
	hide()
	reveal = 0.0

func update_layout() -> void:
	if body == null: return
	var compact := size.x < 600
	var design_size := Vector2(640, 608 if compact else 552)
	var fit := minf(1.0, minf(size.x / (design_size.x + 40), size.y / (design_size.y + 40)))
	body.size = design_size
	body.scale = Vector2.ONE * fit
	body.position = ((size - design_size * fit) * 0.5).round()
	heading.position = Vector2(0, 278)
	heading.size = Vector2(640, 120)
	if compact:
		return_button.position = Vector2(164, 436)
		quit_button.position = Vector2(164, 520)
		return_button.size = Vector2(312, 64)
		quit_button.size = Vector2(312, 64)
	else:
		return_button.position = Vector2(64, 448)
		quit_button.position = Vector2(332, 448)
		return_button.size = Vector2(244, 64)
		quit_button.size = Vector2(244, 64)
	apply_reveal()
	queue_redraw()

func apply_reveal() -> void:
	if body == null: return
	var text_reveal := smoothstep(0.12, 0.9, reveal)
	heading.modulate.a = text_reveal
	heading.position.y = 278 + roundf((1 - text_reveal) * 18)
	var buttons_reveal := smoothstep(0.45, 1.0, reveal)
	return_button.modulate.a = buttons_reveal
	quit_button.modulate.a = buttons_reveal

func _draw() -> void:
	if body == null: return
	var emergence := smoothstep(0, 0.8, reveal)
	var crest_center := body.position + (Vector2(320, 154) + Vector2(0, (1 - emergence) * 24)) * body.scale
	draw_set_transform(crest_center, 0, body.scale * lerpf(0.88, 1, emergence))
	var edge := Color(Color("669bb8"), emergence)
	var snow := Color(Color("edfaff"), emergence)
	var light := Color(Color("bcefff"), emergence)
	var blue := Color(Color("61badd"), emergence)
	# A hexagonal seal belongs to HEXAGON; its crown is cut from ice instead of gold.
	facet([Vector2(-88,-56), Vector2(0,-108), Vector2(88,-56), Vector2(88,44), Vector2(0,96), Vector2(-88,44)], edge)
	facet([Vector2(-82,-52), Vector2(0,-100), Vector2(82,-52), Vector2(82,40), Vector2(0,88), Vector2(-82,40)], Color(Color("21485f"), emergence))
	facet([Vector2(-62,-66), Vector2(-34,-28), Vector2(0,-102), Vector2(34,-28), Vector2(62,-66), Vector2(48,18), Vector2(0,38), Vector2(-48,18)], blue)
	facet([Vector2(-62,-66), Vector2(-34,-28), Vector2(0,-102), Vector2(0,10), Vector2(-48,18)], light)
	facet([Vector2(0,-102), Vector2(34,-28), Vector2(62,-66), Vector2(36,8), Vector2(0,38)], Color(Color("368dbb"), emergence))
	facet([Vector2(0,-102), Vector2(0,-12), Vector2(-16,8), Vector2(-34,-28)], snow)
	facet([Vector2(-48,18), Vector2(0,10), Vector2(48,18), Vector2(0,38)], Color(Color("96d9ef"), emergence))
	draw_rect(Rect2(-10,38,20,18), blue)
	draw_rect(Rect2(-42,56,84,6), snow)
	draw_rect(Rect2(-50,62,100,8), edge)
	for side in [-1, 1]:
		var flip: float = side
		stroke(Vector2(flip*100,74), Vector2(flip*132,30), edge)
		stroke(Vector2(flip*132,30), Vector2(flip*140,-38), edge)
		for i in range(4):
			var x := 110 + i * 8
			var y := 54 - i * 28
			facet([Vector2(flip*x,y),Vector2(flip*(x+24),y-10),Vector2(flip*(x+30),y-30),Vector2(flip*(x+8),y-22)], light)
	# Four fixed glints complete the emblem; no perpetual particle noise.
	for point in [Vector2(-110,-90), Vector2(110,-80), Vector2(-54,-126), Vector2(64,104)]:
		stroke(point - Vector2(4,0), point + Vector2(4,0), snow)
		stroke(point - Vector2(0,4), point + Vector2(0,4), snow)
	draw_set_transform(Vector2.ZERO)

func stroke(a: Vector2, b: Vector2, color: Color) -> void:
	var count := maxi(1, int(a.distance_to(b) / 2))
	for i in range(count + 1):
		draw_rect(Rect2(a.lerp(b, float(i) / count).snapped(Vector2(2,2)), Vector2(2,2)), color)

func facet(points: Array[Vector2], color: Color) -> void:
	var low := INF
	var high := -INF
	for point in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	for y in range(int(low), int(high), 2):
		var hits: Array[float] = []
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i+1) % points.size()]
			var scan := y + 1.0
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				hits.append(a.x + (scan-a.y) * (b.x-a.x) / (b.y-a.y))
		hits.sort()
		for i in range(0, hits.size() - 1, 2):
			var left := roundf(hits[i] / 2) * 2
			draw_rect(Rect2(left, y, roundf(hits[i+1] / 2) * 2 - left, 2), color)
