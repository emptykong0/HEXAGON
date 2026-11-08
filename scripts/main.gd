extends Node2D
const Simulation = preload("res://scripts/simulation.gd")
const BattleAI = preload("res://scripts/battle_ai.gd")
const UI_FONT = preload("res://assets/fonts/Pixel-UI.tres")
const DISPLAY_FONT = preload("res://assets/fonts/Pixel-Display.tres")
const PORT = 24567
const HEX_SIZE = 32.0
const COLORS = [Color("59baff"), Color("ff6f79"), Color("efc66a"), Color("8cd9a0")]
var sim = Simulation.new()
var active := false
var local_mode := false
var players: Array = [1]
var roster: Array = [1]
var dragged := -1
var selected := -1
var pressed_tile := -1
var range_tile := -1
var range_age := 0.0
var accumulator := 0.0
var ai: BattleAI
var ai_difficulty := BattleAI.Difficulty.MEDIUM
var status: Label
var summary: Label
var result_label: Label
var address: LineEdit
var start_button: Button
var menu: VBoxContainer
var mode_body: VBoxContainer
var pve_options: VBoxContainer
var network_options: VBoxContainer
var hud: HBoxContainer
var title: Label
var mode_buttons: Array[Button] = []
var transition: Tween
var transitioning := false
var board_visible := false
var board_slide := 0.0
var board_scale := 1.0
var board_alpha := 1.0
var menu_slide := 0.0
var operations: PanelContainer
var operation_source := -1
var editing_targets := false
var pending_targets: Array = []
var target_painting := false
var paint_button := MOUSE_BUTTON_LEFT
var paint_add := true
var paint_visited: Array = []
var paint_position := Vector2.ZERO
var impact_visuals: Array = []
var seen_impacts: Dictionary = {}
var flight_clock = preload("res://scripts/flight_clock.gd").new()
var hex_meshes: Dictionary = {}
var line_meshes: Dictionary = {}
const ICE_LANCE = preload("res://assets/fx/ice-lance.png")
const ICE_BURST = preload("res://assets/fx/snowflake-burst.png")
var tutorial: PanelContainer
var victory_screen: Control
@onready var landscape_light: ShaderMaterial = $Scenery/Landscape.material

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	build_ui()
	get_viewport().size_changed.connect(update_layout)
	update_layout()
	multiplayer.peer_connected.connect(on_peer_connected)
	multiplayer.peer_disconnected.connect(on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): status.text = "等待开始")
	multiplayer.connection_failed.connect(func(): reset_session(); status.text = "连接失败")
	multiplayer.server_disconnected.connect(func(): reset_session(); status.text = "房主已离线")
	queue_redraw()

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var ui_theme := Theme.new()
	ui_theme.default_font = UI_FONT
	ui_theme.default_font_size = 24
	ui_theme.set_color("font_color", "Label", Color("263f57"))
	ui_theme.set_color("font_color", "Button", Color("263f57"))
	ui_theme.set_color("font_hover_color", "Button", Color("17344f"))
	ui_theme.set_color("font_pressed_color", "Button", Color.WHITE)
	ui_theme.set_color("font_focus_color", "Button", Color("17344f"))
	ui_theme.set_color("font_disabled_color", "Button", Color("879bad"))
	ui_theme.set_stylebox("normal", "Button", button_style(Color("eaf3fa"), Color("b2cbdc")))
	ui_theme.set_stylebox("hover", "Button", button_style(Color("ffffff"), Color("709bb8")))
	ui_theme.set_stylebox("pressed", "Button", button_style(Color("315e7e"), Color("315e7e")))
	ui_theme.set_stylebox("disabled", "Button", button_style(Color("c6d8e5"), Color("b7cddd")))
	ui_theme.set_stylebox("focus", "Button", button_style(Color(0, 0, 0, 0), Color("3c82b4"), 3))
	ui_theme.set_stylebox("normal", "LineEdit", button_style(Color("f7fbff"), Color("b2cbdc")))
	ui_theme.set_color("font_color", "LineEdit", Color("263f57"))
	menu = VBoxContainer.new()
	menu.theme = ui_theme
	menu.add_theme_constant_override("separation", 30)
	canvas.add_child(menu)
	title = Label.new()
	title.text = "HEXAGON"
	title.add_theme_font_override("font", DISPLAY_FONT)
	menu.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	menu.add_child(row)
	for caption in ["单人 PVE", "多人联机"]:
		var index := mode_buttons.size()
		var button := add_button(row, caption, func(): select_mode(index))
		button.toggle_mode = true
		mode_buttons.append(button)
	mode_body = VBoxContainer.new()
	mode_body.custom_minimum_size.y = 210
	mode_body.add_theme_constant_override("separation", 16)
	menu.add_child(mode_body)
	pve_options = VBoxContainer.new()
	pve_options.add_theme_constant_override("separation", 14)
	mode_body.add_child(pve_options)
	add_difficulty_selector(ui_theme)
	var play := add_button(pve_options, "开始游戏", start_pve)
	play.custom_minimum_size.y = 68
	network_options = VBoxContainer.new()
	network_options.add_theme_constant_override("separation", 14)
	mode_body.add_child(network_options)
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	network_options.add_child(host_row)
	add_button(host_row, "建立房间", host_game)
	start_button = add_button(host_row, "开始游戏", start_network_game)
	start_button.disabled = true
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	network_options.add_child(join_row)
	address = LineEdit.new()
	address.placeholder_text = "房主 IP"
	address.text = "127.0.0.1"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address)
	add_button(join_row, "加入房间", join_game)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 24)
	mode_body.add_child(status)
	add_button(menu, "退出游戏", quit_game)
	add_button(menu, "教程", func(): tutorial.show())
	build_tutorial(canvas, ui_theme)
	operations = preload("res://scripts/operation_panel.gd").new()
	canvas.add_child(operations)
	operations.chosen.connect(on_operation_action)
	hud = HBoxContainer.new()
	hud.theme = ui_theme
	hud.add_theme_constant_override("separation", 16)
	canvas.add_child(hud)
	summary = Label.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 24)
	hud.add_child(summary)
	add_button(hud, "退出本局", func(): reset_session())
	add_button(hud, "退出游戏", quit_game)
	hud.hide()
	result_label = Label.new()
	result_label.add_theme_font_override("font", UI_FONT)
	result_label.position = Vector2(0, 177)
	result_label.size = Vector2(1280, 44)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 36)
	result_label.add_theme_color_override("font_color", Color("303f50"))
	canvas.add_child(result_label)
	var result_canvas := CanvasLayer.new()
	result_canvas.layer = 20
	add_child(result_canvas)
	victory_screen = preload("res://scripts/victory_screen.gd").new()
	result_canvas.add_child(victory_screen)
	victory_screen.return_requested.connect(reset_session)
	victory_screen.quit_requested.connect(quit_game)
	victory_screen.reveal_changed.connect(func(amount: float): landscape_light.set_shader_parameter(&"dusk", amount))
	select_mode(0)

func add_difficulty_selector(ui_theme: Theme) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	pve_options.add_child(row)
	var label := Label.new()
	label.text = "AI 难度"
	label.custom_minimum_size.x = 100
	row.add_child(label)
	var group := ButtonGroup.new()
	ui_theme.set_type_variation("DifficultyButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var base: String = "pressed" if state == "hover_pressed" else state
		var style: StyleBoxFlat = ui_theme.get_stylebox(base, "Button").duplicate()
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		ui_theme.set_stylebox(state, "DifficultyButton", style)
	ui_theme.set_color("font_hover_pressed_color", "DifficultyButton", Color.WHITE)
	for level in range(BattleAI.LABELS.size()):
		var button := add_button(row, BattleAI.LABELS[level], func(): ai_difficulty = level)
		button.theme_type_variation = "DifficultyButton"
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.button_pressed = level == ai_difficulty

func button_style(fill: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.shadow_color = Color("7292ac")
	style.shadow_size = 0 if fill.a == 0 else 4
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style

func select_mode(index: int) -> void:
	if active or transitioning:
		return
	if multiplayer.multiplayer_peer != null:
		reset_session()
	for i in range(mode_buttons.size()):
		mode_buttons[i].button_pressed = i == index
	pve_options.visible = index == 0
	network_options.visible = index == 1
	status.text = ""

func show_match() -> void:
	transitioning = true
	board_visible = false
	board_slide = get_viewport_rect().size.y * 0.8
	board_scale = 0.62
	board_alpha = 0.0
	set_menu_input(false)
	transition = create_tween()
	transition.set_parallel(true)
	transition.tween_property(self, "menu_slide", -get_viewport_rect().size.x * 0.65, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	transition.tween_property(menu, "modulate:a", 0.0, 0.36)
	transition.chain().tween_callback(func(): menu.hide(); board_visible = true)
	transition.chain().tween_property(self, "board_slide", 0.0, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	transition.parallel().tween_property(self, "board_alpha", 1.0, 0.35)
	transition.parallel().tween_property(landscape_light, "shader_parameter/match_mist", 1.0, 0.35)
	transition.chain().tween_property(self, "board_scale", 1.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition.chain().tween_callback(func(): transitioning = false; hud.show())

func set_menu_input(enabled: bool) -> void:
	for button in menu.find_children("*", "Button", true, false):
		button.disabled = not enabled
	address.editable = enabled
	if enabled:
		start_button.disabled = multiplayer.multiplayer_peer == null or not multiplayer.is_server()

func add_button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var side_margin := 16.0 if viewport_size.x < 520 else 32.0
	var menu_width := minf(560.0, viewport_size.x - 2 * side_margin)
	title.add_theme_font_size_override("font_size", int(maxf(24, floorf(minf(72, menu_width / 7) / 12) * 12)))
	var minimum := menu.get_combined_minimum_size()
	menu.size = Vector2(maxf(menu_width, minimum.x), minimum.y)
	menu.position = Vector2((viewport_size.x - menu.size.x) * 0.5 + menu_slide, maxf(8.0, (viewport_size.y - menu.size.y) * 0.5))
	hud.position = Vector2(28, 22)
	hud.size.x = viewport_size.x - 56
	var play_area := board_area()
	result_label.position = Vector2(play_area.position.x, play_area.get_center().y - 150)
	result_label.size = Vector2(play_area.size.x, 44)
	if tutorial != null:
		tutorial.position = Vector2(32, 28)
		tutorial.size = Vector2(maxf(240, viewport_size.x - 64), maxf(240, viewport_size.y - 56))
	update_operations()
	queue_redraw()

func quit_game() -> void:
	active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit()

func reset_session() -> void:
	victory_screen.dismiss()
	landscape_light.set_shader_parameter(&"match_mist", 0.0)
	result_label.show()
	impact_visuals.clear()
	seen_impacts.clear()
	flight_clock.reset()
	close_operations()
	if tutorial != null: tutorial.hide()
	range_tile = -1
	range_age = 0.0
	if transition != null and transition.is_valid():
		transition.kill()
	transitioning = false
	board_visible = false
	board_slide = 0.0
	board_scale = 1.0
	board_alpha = 1.0
	menu_slide = 0.0
	menu.modulate.a = 1.0
	menu.show()
	hud.hide()
	active = false
	local_mode = false
	dragged = -1
	selected = -1
	pressed_tile = -1
	accumulator = 0
	ai = null
	last_sent_tick = -1
	result_label.text = ""
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players = [1]
	roster = [1]
	start_button.disabled = true
	status.text = ""
	summary.text = ""
	set_menu_input(true)
	update_layout()
	queue_redraw()

func start_pve() -> void:
	reset_session()
	local_mode = true
	players = [1, -1]
	roster = players.duplicate()
	sim.setup(players)
	ai = BattleAI.new(sim, -1, ai_difficulty)
	active = true
	status.text = "PVE"
	show_match()

func host_game() -> void:
	reset_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 3)
	if error != OK:
		status.text = "开房失败（%s）" % error
		return
	multiplayer.multiplayer_peer = peer
	start_button.disabled = false
	update_lobby()

func join_game() -> void:
	var ip := address.text.strip_edges()
	if ip.is_empty():
		status.text = "地址为空"
		return
	reset_session()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT)
	if error != OK:
		status.text = "连接失败（%s）" % error
		return
	multiplayer.multiplayer_peer = peer
	status.text = "正在连接 %s:%s …" % [ip, PORT]

func on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if active:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players.append(id)
	update_lobby()

func on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	if active:
		status.text = "玩家离线"
	else:
		update_lobby()

func update_lobby() -> void:
	status.text = "%s/4 人" % players.size()

func start_network_game() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or active:
		return
	if players.size() < 2:
		status.text = "人数不足"
		return
	roster = players.duplicate()
	sim.setup(roster)
	accumulator = 0
	active = true
	start_button.disabled = true
	begin_match.rpc(sim.snapshot(), roster)
	status.text = "联机对局"
	show_match()

@rpc("authority", "call_remote", "reliable")
func begin_match(state: Dictionary, match_roster: Array) -> void:
	roster = match_roster
	sim.restore(state)
	flight_clock.reset(sim.tick)
	active = true
	status.text = "联机对局"
	show_match()
	queue_redraw()

@rpc("authority", "call_remote", "reliable")
func receive_state(state: Dictionary) -> void:
	if active:
		sim.restore(state)
		flight_clock.receive(sim.tick)
		queue_redraw()

@rpc("any_peer", "call_remote", "reliable")
func request_dispatch(source: int, target: int) -> void:
	if multiplayer.is_server() and active:
		var actor := multiplayer.get_remote_sender_id()
		if players.has(actor):
			sim.dispatch(actor, source, [target])

func local_player() -> int:
	return 1 if local_mode or multiplayer.multiplayer_peer == null else multiplayer.get_unique_id()

func _process(delta: float) -> void:
	for hit in impact_visuals:
		hit.age += delta
	impact_visuals = impact_visuals.filter(func(hit): return hit.age < 0.85)
	if range_tile >= 0:
		range_age += delta
	if active and not transitioning and (local_mode or multiplayer.is_server()):
		accumulator += delta
		while accumulator >= 0.1 and not sim.finished:
			accumulator -= 0.1
			sim.advance()
			if ai != null:
				ai.step()
		if not local_mode:
			# Prototype snapshots at 10 Hz, independent of render frame rate.
			if sim.tick != last_sent_tick:
				last_sent_tick = sim.tick
				var state: Dictionary = sim.snapshot()
				for id in multiplayer.get_peers():
					var peer: ENetPacketPeer = multiplayer.multiplayer_peer.get_peer(id)
					if peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
						receive_state.rpc_id(id, state)
	if active and not transitioning:
		if local_mode or multiplayer.is_server():
			flight_clock.advance_local(sim.tick, 0.0 if sim.finished else accumulator, Simulation.TICKS_PER_SECOND)
		elif not sim.finished:
			flight_clock.advance_remote(delta, Simulation.TICKS_PER_SECOND)
		for hit in sim.impacts:
			if not seen_impacts.has(hit.id):
				seen_impacts[hit.id] = true
				impact_visuals.append({"target": hit.target, "owner": hit.owner, "count": hit.count, "age": 0.0, "source": hit.source})
	if active:
		result_label.text = sim.result_for(local_player())
		if result_label.text == "胜利":
			result_label.hide()
			hud.hide()
			victory_screen.present()
		if not result_label.text.is_empty():
			range_tile = -1
			dragged = -1
			selected = -1
			pressed_tile = -1
		if selected >= 0 and sim.tiles[selected].owner != local_player():
			selected = -1
		if dragged >= 0 and sim.tiles[dragged].owner != local_player():
			dragged = -1
		if sim.finished:
			accumulator = 0
		if selected < 0 or not sim.can_command(local_player(), selected):
			close_operations()
	if active:
		update_summary()
	update_layout()
	queue_redraw()

var last_sent_tick := -1

func update_summary() -> void:
	var entries: Array[String] = []
	for i in range(roster.size()):
		var owner: int = roster[i]
		var owned := 0
		for tile in sim.tiles:
			if tile.owner == owner:
				owned += 1
		entries.append("%s%s %s 块" % ["● " if owner == local_player() else "", ["蓝方", "红方", "金方", "绿方"][i], owned])
	summary.text = "   |   ".join(entries) + "      时间 %ss" % (sim.tick / 10)

func center(tile: Dictionary) -> Vector2:
	var origin := get_viewport_rect().size * 0.5 + Vector2(0, 60)
	return origin + HEX_SIZE * Vector2(sqrt(3.0) * (tile.q + tile.r * 0.5), 1.5 * tile.r)

func tile_at(point: Vector2) -> int:
	point = board_transform().affine_inverse() * point
	for tile in sim.tiles:
		var polygon := hex_polygon(center(tile), HEX_SIZE)
		if Geometry2D.is_point_in_polygon(point, polygon):
			return tile.id
	return -1

func hex_polygon(pos: Vector2, size: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(6):
		result.append(pos + Vector2.from_angle(deg_to_rad(60 * i - 30)) * size)
	return result

func owner_color(owner: int) -> Color:
	var index: int = roster.find(owner)
	return COLORS[index] if index >= 0 else Color("65738a")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == paint_button:
		target_painting = false
	if editing_targets and active and not transitioning and not sim.finished and sim.can_command(local_player(), selected) and event is InputEventMouseMotion and target_painting:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var steps := maxi(1, int(ceil(paint_position.distance_to(point) / 4.0)))
		for i in range(1, steps + 1):
			paint_target(tile_at(paint_position.lerp(point, float(i) / steps)))
		paint_position = point
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not active or transitioning or sim.finished or sim.eliminated.has(local_player()):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	update_operations()
	if selected < 0 or not sim.can_command(local_player(), selected):
		return
	for entry in operations.items:
		if event.keycode == entry.key or event.physical_keycode == entry.key:
			get_viewport().set_input_as_handled()
			if not entry.get("disabled", false):
				on_operation_action(entry.action)
			return

func _unhandled_input(event: InputEvent) -> void:
	if not active or transitioning or sim.finished or sim.eliminated.has(local_player()):
		return
	if event is InputEventMouseButton:
		if editing_targets and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			if event.pressed:
				target_painting = true
				paint_button = event.button_index
				paint_visited.clear()
				paint_position = get_global_transform_with_canvas().affine_inverse() * event.position
				paint_add = event.button_index == MOUSE_BUTTON_LEFT
				paint_target(tile_at(paint_position))
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			close_operations()
			range_tile = -1
			dragged = -1
			selected = -1
			pressed_tile = -1
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var target := tile_at(get_global_transform_with_canvas().affine_inverse() * event.position)
			if event.pressed:
				if selected < 0:
					range_tile = target
					range_age = 0.0
				pressed_tile = target
				dragged = -1
				if target >= 0 and sim.tiles[target].owner == local_player():
					dragged = target
			else:
				if dragged >= 0 and target >= 0 and dragged != target:
					if submit_dispatch(dragged, target):
						selected = -1
						range_tile = -1
					else:
						selected = dragged
				elif pressed_tile >= 0 and target == pressed_tile:
					if selected >= 0 and selected != target:
						if submit_dispatch(selected, target):
							selected = -1
							range_tile = -1
					elif dragged >= 0:
						selected = dragged
				elif target < 0:
					selected = -1
					range_tile = -1
				dragged = -1
				pressed_tile = -1
		if selected < 0:
			close_operations()
		queue_redraw()

func submit_dispatch(source: int, target: int) -> bool:
	if source < 0 or source >= sim.tiles.size() or sim.tiles[source].owner != local_player():
		return false
	if not sim.in_range(source, target) or sim.dispatchable_count(source) <= 0:
		return false
	if local_mode or multiplayer.is_server():
		return sim.dispatch(local_player(), source, [target])
	else:
		request_dispatch.rpc_id(1, source, target)
		return true

func range_brightness(tile: Dictionary) -> float:
	if range_tile < 0 or not sim.in_range(range_tile, tile.id):
		return 0.0
	var age := range_age - sim.hex_distance(sim.tiles[range_tile], tile) * 0.035
	if age <= 0:
		return 0.0
	if age < 0.10:
		return smoothstep(0.0, 0.10, age)
	return lerpf(1.0, 0.42, smoothstep(0.10, 0.30, age))

func _draw() -> void:
	if not board_visible or (victory_screen != null and victory_screen.visible):
		return
	var transform := board_transform()
	draw_set_transform_matrix(transform)
	self_modulate.a = board_alpha
	draw_board()

func board_area() -> Rect2:
	var viewport_size := get_viewport_rect().size
	return Rect2(24, 108, maxf(120, viewport_size.x - 324), maxf(120, viewport_size.y - 140))

func map_bounds() -> Rect2:
	if sim.tiles.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var bounds := Rect2(center(sim.tiles[0]), Vector2.ZERO)
	for tile in sim.tiles:
		var pos := center(tile)
		bounds = bounds.expand(pos - Vector2(HEX_SIZE, HEX_SIZE))
		bounds = bounds.expand(pos + Vector2(HEX_SIZE, HEX_SIZE + 5))
	return bounds

func board_transform() -> Transform2D:
	var area := board_area()
	var bounds := map_bounds()
	var fit := minf(1.0, minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y))
	var zoom := board_scale * fit
	return Transform2D(0, Vector2.ONE * zoom, 0, area.get_center() - bounds.get_center() * zoom + Vector2(0, board_slide))

func draw_board() -> void:
	var font := DISPLAY_FONT
	var orders: Array = []
	if selected >= 0:
		orders = pending_targets if editing_targets else sim.building_at(selected).get("targets", [])
	# Draw all shadows first so adjacent tiles share the same raised surface.
	for tile in sim.tiles:
		var pos := center(tile)
		pixel_polygon(hex_polygon(pos + Vector2(0, 5), HEX_SIZE - 1), Color(0, 0, 0, 0.14))
		pixel_polygon(hex_polygon(pos + Vector2(0, 3), HEX_SIZE - 2), Color("b9b9b9"))
	for tile in sim.tiles:
		var pos := center(tile) + impact_offset(tile.id)
		var color := owner_color(tile.owner)
		var light := range_brightness(tile)
		var polygon := hex_polygon(pos, HEX_SIZE - 2)
		if light > 0:
			var halo := hex_polygon(pos, HEX_SIZE - 0.5)
			halo.append(halo[0])
			pixel_polyline(halo, Color(0.63, 0.85, 1.0, light * 0.75), 3.5, true)
		var target_color := Color("b7dafa") if orders.has(tile.id) else Color.WHITE
		pixel_polygon(polygon, Color("ededed").lerp(target_color, 1.0 if orders.has(tile.id) else light))
		pixel_polygon(hex_polygon(pos + Vector2(0, -1), HEX_SIZE - 4), Color("fafafa").lerp(target_color, 1.0 if orders.has(tile.id) else light))
		# Upper edges catch the light; lower edges describe a shallow bevel.
		for i in range(6):
			var edge_color := Color("ffffff") if i >= 3 else Color("d0d0d0")
			edge_color = edge_color.lerp(Color.WHITE, light)
			pixel_line(polygon[i], polygon[(i + 1) % 6], edge_color, 1.3, true)
		if tile.owner != 0:
			var outline := hex_polygon(pos, HEX_SIZE - 3)
			outline.append(outline[0])
			pixel_polyline(outline, color.darkened(0.15), 1.8, true)
			draw_rect(Rect2((pos + Vector2(-2, -22)).snapped(Vector2(2, 2)), Vector2(4, 4)), color.darkened(0.15))
		if tile.building_id >= 0:
			draw_pixel_building(pos, color.darkened(0.4), sim.building_at(tile.id))
		var label := str(tile.count)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font, pos + Vector2(-width / 2, 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("30343b"))
	draw_range_boundary()
	for fleet in sim.fleets:
		var a := center(sim.tiles[fleet.source])
		var b := center(sim.tiles[fleet.target])
		var elapsed := maxf(0, flight_clock.time - fleet.start)
		var progress := clampf(elapsed / fleet.duration, 0, 1)
		var direction := (b - a).normalized()
		var pos := a.lerp(b, progress)
		# Brief compression at launch; then the faceted lance travels tip-first.
		var scale_fx := lerpf(0.35, 0.9, minf(1, elapsed / 1.2))
		draw_set_transform_matrix(board_transform() * Transform2D((b-a).angle(), Vector2.ONE * scale_fx, 0, pos))
		var frame := int(elapsed * 3) % 24
		draw_texture_rect_region(ICE_LANCE, Rect2(-146, -32, 176, 64), Rect2((frame % 3) * 176, (frame / 3) * 64, 176, 64))
		draw_set_transform_matrix(board_transform())
		# Small faction seal keeps the ice legible for every player.
		draw_rect(Rect2((pos - direction * 18).snapped(Vector2(2, 2)) - Vector2(2, 2), Vector2(4, 4)), owner_color(fleet.owner))
	for hit in impact_visuals:
		draw_ice_impact(hit)
	if selected >= 0:
		var selection := hex_polygon(center(sim.tiles[selected]), HEX_SIZE - 6)
		selection.append(selection[0])
		pixel_polyline(selection, owner_color(local_player()).darkened(0.4), 3, true)
		for target in orders:
			var marker := hex_polygon(center(sim.tiles[target]), HEX_SIZE - 6)
			marker.append(marker[0])
			pixel_polyline(marker, Color("315e7e"), 2, true)
	if dragged >= 0:
		pixel_line(center(sim.tiles[dragged]), board_transform().affine_inverse() * get_global_mouse_position(), owner_color(local_player()).darkened(0.3), 2, true)

func draw_range_boundary() -> void:
	if range_tile < 0:
		return
	var owner: int = sim.tiles[range_tile].owner
	var boundary_color := Color("ce414c") if owner != 0 and owner != local_player() else Color(0.22, 0.40, 0.54)
	var covered: Dictionary = {}
	for tile in sim.tiles:
		if sim.in_range(range_tile, tile.id):
			covered[Vector2i(tile.q, tile.r)] = true
	for tile in sim.tiles:
		var cell := Vector2i(tile.q, tile.r)
		if not covered.has(cell):
			continue
		var light := range_brightness(tile)
		if light <= 0:
			continue
		var polygon := hex_polygon(center(tile), HEX_SIZE - 1)
		for edge in range(6):
			if not covered.has(cell + Simulation.HEX_NEIGHBORS[edge]):
				pixel_line(polygon[edge], polygon[(edge + 1) % 6], Color(boundary_color, minf(1.0, light / 0.42)), 2.8, true)

func close_operations() -> void:
	operation_source = -1
	target_painting = false
	paint_visited.clear()
	editing_targets = false
	pending_targets.clear()
	if operations != null: operations.hide()

func update_operations() -> void:
	if operations == null:
		return
	if selected < 0 or not active or transitioning or not sim.can_command(local_player(), selected):
		operations.hide()
		return
	var building: Dictionary = sim.building_at(selected)
	var entries: Array
	if editing_targets:
		entries = [
			{"action": "confirm", "label": "确认", "key": KEY_R, "key_label": "R"},
			{"action": "cancel", "label": "取消", "key": KEY_F, "key_label": "F"}]
	elif building.is_empty():
		entries = [
			{"action": "build", "label": "指挥塔", "amount": "10", "key": KEY_Q, "key_label": "Q", "disabled": sim.tiles[selected].count < 10},
			{"action": "build_collection", "label": "收集塔", "amount": "10", "key": KEY_W, "key_label": "W", "disabled": sim.tiles[selected].count < 10}]
	elif building.type == "command_tower":
		entries = [
			{"action": "targets", "label": "设置目标", "key": KEY_Q, "key_label": "Q"},
			{"action": "stop", "label": "停止出兵", "key": KEY_W, "key_label": "W", "disabled": building.get("targets", []).is_empty()},
			{"action": "demolish", "label": "拆毁", "amount": "+5", "key": KEY_E, "key_label": "E"}]
	else:
		var upgraded: bool = int(building.get("level", 1)) >= 2
		var upgrade_entry := {"action": "upgrade", "label": "已升级" if upgraded else "升级", "key": KEY_Q, "key_label": "Q", "disabled": upgraded or sim.tiles[selected].count < 20}
		if not upgraded: upgrade_entry.amount = "20"
		entries = [
			{"action": "targets", "label": "设置目标", "key": KEY_A, "key_label": "A"},
			{"action": "stop", "label": "停止输送", "key": KEY_W, "key_label": "W", "disabled": building.get("targets", []).is_empty()},
			upgrade_entry,
			{"action": "demolish", "label": "拆毁", "amount": "+%s" % sim.building_refund(selected), "key": KEY_E, "key_label": "E"}]
	if not editing_targets:
		entries.append({"action": "close", "label": "取消选择", "key": KEY_F, "key_label": "F"})
	var caption := "目标设置" if editing_targets else ("地块" if building.is_empty() else ("指挥塔" if building.type == "command_tower" else "收集塔"))
	var target_count: int = pending_targets.size() if editing_targets else building.get("targets", []).size()
	var collector: bool = building.get("type", "") == "collection_tower"
	var settings: Dictionary = sim.collection_settings(selected) if collector else {}
	if collector and not editing_targets and int(building.get("level", 1)) >= 2: caption = "收集塔 2级"
	var target_limit: int = sim.auto_target_limit(selected)
	operations.set_context(caption, sim.tiles[selected].count, sim.attack_range(selected), target_count if target_limit != 0 else -1, settings.get("storage_cap", 0), settings.get("radius", 1), target_limit)
	if operation_source != selected or operations.items != entries or not operations.visible:
		var animate: bool = operation_source != selected or not operations.visible
		operation_source = selected
		operations.open(entries, animate)
	operations.size = Vector2(252, 0)
	operations.position = Vector2(get_viewport_rect().size.x - 276, maxf(108, (get_viewport_rect().size.y - operations.get_combined_minimum_size().y) * 0.5))

func on_operation_action(action: String) -> void:
	get_viewport().set_input_as_handled()
	target_painting = false
	if editing_targets and action == "close":
		return
	dragged = -1
	pressed_tile = -1
	if selected < 0 or not sim.can_command(local_player(), selected):
		close_operations()
		return
	match action:
		"targets":
			if sim.auto_target_limit(selected) == 0:
				return
			editing_targets = true
			pending_targets = sim.building_at(selected).get("targets", []).duplicate()
		"cancel":
			editing_targets = false
			pending_targets.clear()
		"confirm":
			submit_building_command("targets", selected, pending_targets)
			editing_targets = false
			pending_targets = []
		"build", "build_collection", "upgrade", "demolish", "stop":
			submit_building_command(action, selected, [])
		"close":
			selected = -1
			range_tile = -1
			close_operations()
	update_operations()

func paint_target(target: int) -> void:
	if target < 0 or target == selected or not sim.in_range(selected, target) or paint_visited.has(target):
		return
	paint_visited.append(target)
	if paint_add and not pending_targets.has(target):
		if sim.auto_target_limit(selected) == 1:
			pending_targets.clear()
		pending_targets.append(target)
	elif not paint_add:
		pending_targets.erase(target)

func submit_building_command(action: String, source: int, targets: Array) -> void:
	if local_mode or multiplayer.is_server():
		apply_building_command(local_player(), action, source, targets)
	else:
		request_building_command.rpc_id(1, action, source, targets)

func apply_building_command(actor: int, action: String, source: int, targets: Array) -> bool:
	if not active or transitioning: return false
	match action:
		"build": return sim.build(actor, source, "command_tower")
		"build_collection": return sim.build(actor, source, "collection_tower")
		"upgrade": return sim.upgrade(actor, source)
		"demolish": return sim.demolish(actor, source)
		"targets": return sim.set_targets(actor, source, targets)
		"stop": return sim.set_targets(actor, source, [])
	return false

@rpc("any_peer", "call_remote", "reliable")
func request_building_command(action: String, source: int, targets: Array) -> void:
	if multiplayer.is_server() and players.has(multiplayer.get_remote_sender_id()):
		apply_building_command(multiplayer.get_remote_sender_id(), action, source, targets)

func build_tutorial(canvas: CanvasLayer, ui_theme: Theme) -> void:
	tutorial = PanelContainer.new()
	tutorial.theme = ui_theme
	tutorial.add_theme_stylebox_override("panel", button_style(Color("edf5fb"), Color("b2cbdc")))
	canvas.add_child(tutorial)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	tutorial.add_child(column)
	var heading := Label.new()
	heading.text = "教程"
	heading.add_theme_font_size_override("font_size", 36)
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := Label.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "单人难度\n\n在首页选择低、中或高。三档都会建造指挥塔和收集塔。低档优先攻占易得的地块，中档会朝对手推进并升级收集塔，高档还会增援受袭地块、分两次出兵合攻。\n\n基础操作\n\n拖动己方地块到目标，或先点击己方地块再点击目标，普通地块全量出兵，指挥塔保留 15 点。右键取消选择。己方目标用于增援，敌方和无主目标用于进攻。普通地块射程为 2 格。\n\n每秒增长 1 点能量；无主地块自然增长上限 15，己方与敌方为 50，增援可超过上限。敌方数量扣至 0 时立即占领；攻击已为 0 的地块时，占领并保留全部抵达能量。每个目标发射一枚冰锥，命中时一次结算整批能量；超过守方的剩余能量留在占领后的地块。失去全部地块即出局。\n\n建造与拆毁\n\n点击己方地块，在地图右侧操作区选择建筑。费用从该格能量中扣除，每格限一个建筑，立即建成。选择已有建筑的地块，点击“拆毁”返还累计投入的一半费用到本格。操作区与地图分开，不会遮挡周围地块。\n\n快捷键\n\nQ：建造指挥塔、设置指挥塔目标或升级收集塔；A：设置收集塔目标；W：建造收集塔、停止出兵或停止输送；E：拆毁；R：确认目标；F：取消目标编辑或取消选择。快捷键与按钮执行相同操作，数量不足、出局或对局结束时不可执行。\n\n指挥塔\n\n建造费用 10，拆毁返还 5，所在格射程提升至 3 格。点击“设置目标”，依次点击射程内的任意其他地块，再点击“确认”。左键单击或按住滑动添加目标，右键单击或按住滑动取消目标；目标只显示蓝色标记，不显示选择连线。“取消”或 F 放弃本次编辑，保留原指令。\n\n确认后每秒自动派出超过 15 点的部分，向所有目标平均分配，余数跨批次轮流分配；手动出兵也保留至少 15 点，不足时等待增长。目标成为己方后仍保留并持续增援。“停止出兵”清空目标。建筑被占领后保留，目标配置清空，由新主人重新设置。\n\n收集塔\n\n建造费用 10，拆毁返还 5，1 级收集范围为相邻六格，仅收集己方地块，始终跳过指挥塔和其他收集塔所在格。每秒将邻格超过 15 点的部分收至塔所在格，邻格至少保留 15 点。塔所在格达到 150 后停止收集，未收取部分留在原格；可以正常出兵，腾出容量后继续收集。点击“升级”或 Q 消耗本格 20 点升到 2 级，收集容量提升至 500，半径提升至 2 格（含边界），仍跳过指挥塔及其他收集塔，来源格保留 15 点。最多升级一次，被占领后等级保留；升级后拆毁返还 15 点。自然增长上限仍为 50，增援与拆毁返还可超过收集容量，已有数量不会被削减。\n\n点击“设置目标”或 A，为收集塔设置一个输送目标：左键点击选择，再点击另一格会替换；按住滑动时保留最后一个有效目标，右键移除。R 确认，F 取消编辑并保留原目标。目标须在出兵射程 2 格内（含边界），可为己方、敌方或无主地块。确认一秒后开始，每秒先收集，再以一枚冰锥输送塔内全部能量，塔本身不保留 15 点；供能地块仍保留至少 15 点。没有能量时等待，获得能量后继续输送。“停止输送”或 W 清空目标，但继续收集。升级保留目标与 2 格出兵射程；目标易主后继续按抵达时归属增援或进攻。塔被占领后清空目标，由新主人重新设置。\n\n联机\n\n所有玩家加入同一 Radmin VPN 网络，房主建立房间，其他玩家输入房主的 VPN IPv4 地址加入，由房主开始游戏。"
	scroll.add_child(body)
	add_button(column, "返回", func(): tutorial.hide())
	tutorial.hide()

# Cache the pixel silhouettes as meshes; changing light/color needs no new geometry.
# Keep the analytic hex for hit testing and the same two-unit raster for the artwork.
func pixel_polygon(points: PackedVector2Array, color: Color) -> void:
	var origin := (points[0] + points[3]) * 0.5
	var radius := snappedf(points[0].distance_to(origin), 0.01)
	if not hex_meshes.has(radius):
		var local_points := hex_polygon(Vector2.ZERO, radius)
		var rects: Array[Rect2] = []
		for y in range(int(floorf(-radius / 2)) * 2, int(ceilf(radius / 2)) * 2, 2):
			var hits: Array[float] = []
			var scan := float(y) + 1.0
			for i in range(local_points.size()):
				var a := local_points[i]
				var b := local_points[(i + 1) % local_points.size()]
				if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
					hits.append(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y))
			if hits.size() >= 2:
				hits.sort()
				var left := roundf(hits[0] / 2) * 2
				rects.append(Rect2(left, y, roundf(hits[-1] / 2) * 2 - left, 2))
		hex_meshes[radius] = pixel_rect_mesh(rects)
	draw_mesh(hex_meshes[radius], null, Transform2D(0, origin.snapped(Vector2(2, 2))), color)

func pixel_line(a: Vector2, b: Vector2, color: Color, width: float = 2, _aa: bool = false) -> void:
	var origin := a.snapped(Vector2(2, 2))
	var direction := b.snapped(Vector2(2, 2)) - origin
	var thickness := maxf(2, roundf(width / 2) * 2)
	var key := Vector3(direction.x, direction.y, thickness)
	if not line_meshes.has(key):
		# Drag previews can have arbitrary lengths; keep their geometry cache bounded.
		if line_meshes.size() >= 256: line_meshes.clear()
		var steps := maxi(1, int(ceilf(maxf(absf(direction.x), absf(direction.y)) / 2)))
		var rects: Array[Rect2] = []
		for i in range(steps + 1):
			var point := (direction * float(i) / steps).snapped(Vector2(2, 2))
			rects.append(Rect2(point - Vector2.ONE * thickness / 2, Vector2.ONE * thickness))
		line_meshes[key] = pixel_rect_mesh(rects)
	draw_mesh(line_meshes[key], null, Transform2D(0, origin), color)

func pixel_rect_mesh(rects: Array[Rect2]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for rect in rects:
		for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, rect.position, rect.end, Vector2(rect.position.x, rect.end.y)]:
			vertices.append(Vector3(point.x, point.y, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func pixel_polyline(points: PackedVector2Array, color: Color, width: float = 2, _aa: bool = false) -> void:
	for i in range(points.size() - 1):
		pixel_line(points[i], points[i + 1], color, width)

func draw_pixel_building(pos: Vector2, ink: Color, building: Dictionary) -> void:
	pos = (pos + Vector2(0, -20)).snapped(Vector2(2, 2))
	if building.type == "command_tower":
		draw_rect(Rect2(pos + Vector2(-6, 2), Vector2(12, 4)), ink)
		draw_rect(Rect2(pos + Vector2(-4, -6), Vector2(8, 10)), ink)
		draw_rect(Rect2(pos + Vector2(-2, -4), Vector2(4, 4)), Color("c8e9fa"))
		draw_rect(Rect2(pos + Vector2(0, -12), Vector2(2, 6)), ink)
		draw_rect(Rect2(pos + Vector2(2, -12), Vector2(6, 4)), Color("398ed4"))
	else:
		draw_rect(Rect2(pos + Vector2(-8, -6), Vector2(16, 12)), ink)
		draw_rect(Rect2(pos + Vector2(-6, -4), Vector2(12, 8)), Color("bfdde8"))
		draw_rect(Rect2(pos + Vector2(-2, -2), Vector2(4, 4)), ink)
		if int(building.get("level", 1)) >= 2:
			draw_rect(Rect2(pos + Vector2(-6, -10), Vector2(4, 4)), ink)
			draw_rect(Rect2(pos + Vector2(2, -10), Vector2(4, 4)), ink)

func impact_offset(tile: int) -> Vector2:
	for hit in impact_visuals:
		if hit.target == tile and hit.age < 0.22:
			var direction := (center(sim.tiles[hit.target]) - center(sim.tiles[hit.source])).normalized()
			return (direction * sin(hit.age * 90) * 5 * (1 - hit.age / 0.22)).snapped(Vector2(2, 2))
	return Vector2.ZERO

func draw_ice_impact(hit: Dictionary) -> void:
	var pos := center(sim.tiles[hit.target])
	var age: float = hit.age
	if age < 0.055:
		pixel_polygon(hex_polygon(pos, HEX_SIZE - 3), Color("e2fcff"))
		pixel_line(pos - Vector2(14, 0), pos + Vector2(14, 0), Color.WHITE, 4)
		pixel_line(pos - Vector2(0, 14), pos + Vector2(0, 14), Color.WHITE, 4)
	# Accelerate the stock frost burst for a sharp 0.8s hit and a falling-ice recovery.
	var frame := mini(96, int(age / 0.85 * 97))
	var scale_fx := 0.8
	draw_set_transform_matrix(board_transform() * Transform2D(0, Vector2.ONE * scale_fx, 0, pos))
	draw_texture_rect_region(ICE_BURST, Rect2(-70, -60, 140, 120), Rect2((frame % 10) * 140, (frame / 10) * 120, 140, 120))
	draw_set_transform_matrix(board_transform())
	# Solid dark-edged shards retain punch against the white board.
	for i in range(8):
		var angle: float = i * TAU / 8 + hit.target * 0.3
		var distance := 4 + 30 * (1 - pow(1 - minf(1, age / 0.6), 3))
		var point := pos + Vector2.from_angle(angle) * distance + Vector2(0, age * age * 30)
		var size := 4.0 if age < 0.32 else 2.0
		if age < 0.65:
			draw_rect(Rect2(point.snapped(Vector2(2, 2)), Vector2(size + 2, size + 2)), Color("3976a3"))
			draw_rect(Rect2(point.snapped(Vector2(2, 2)), Vector2(size, size)), Color("c5f6ff"))

