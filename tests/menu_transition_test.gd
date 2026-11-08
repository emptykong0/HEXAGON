extends SceneTree
var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test-results/" + label + ".png")

func click_button(button: Button) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = button.get_global_rect().get_center()
		root.push_input(event, true)
		await process_frame

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var landscape: TextureRect = game.get_node("Scenery/Landscape")
	check(landscape.get_global_rect().is_equal_approx(game.get_viewport_rect()), "landscape fills the startup viewport")
	check(not game.active and not game.board_visible and game.menu.visible, "startup shows menu only")
	await capture("menu-home")
	var levels: Array[Button] = []
	var play: Button
	for button in game.pve_options.find_children("*", "Button", true, false):
		if button.text == "开始游戏":
			play = button
		else:
			levels.append(button)
	check(levels.size() == 3 and levels[1].button_pressed, "single-player menu defaults to medium")
	for i in [2, 0, 1]:
		await click_button(levels[i])
		check(levels[i].button_pressed and game.ai_difficulty == i, "difficulty button selects its level")
		await click_button(play)
		check(game.active and game.ai != null and game.ai.difficulty == i, "play button starts the selected AI")
		game.reset_session()
		await process_frame
		check(game.ai == null and levels[i].button_pressed, "leaving clears the AI and retains the menu choice")
	game.select_mode(1)
	game.host_game()
	check(not game.board_visible and not game.start_button.disabled and not levels[0].is_visible_in_tree() and game.ai == null, "lobby keeps board and difficulty hidden, with no AI")
	game.start_network_game()
	check(not game.active and not game.transitioning, "insufficient players stay in lobby")
	game.reset_session()
	game.select_mode(0)
	game.start_pve()
	var source := -1
	for tile in game.sim.tiles:
		if tile.owner == 1: source = tile.id
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = game.center(game.sim.tiles[source])
	game._unhandled_input(event)
	check(game.dragged == -1, "transition blocks map input")
	await create_timer(0.22).timeout
	check(game.menu_slide < 0 and game.menu.modulate.a < 1 and not game.board_visible, "menu slides left and fades first")
	check(game.sim.tick == 0, "simulation waits for reveal")
	await capture("menu-departure")
	await create_timer(0.48).timeout
	check(game.board_visible and game.board_slide > 0 and game.board_scale < 1, "map rises at small scale")
	await capture("map-arrival")
	await create_timer(0.9).timeout
	check(not game.transitioning and not game.menu.visible and game.hud.visible, "reveal finishes in match view")
	check(is_equal_approx(game.board_scale, 1.0) and is_zero_approx(game.board_slide), "map reaches full scale")
	await capture("map-ready")
	# Verify transformed hit testing after an actual viewport resize.
	root.content_scale_size = Vector2i(900, 700)
	root.size = Vector2i(900, 700)
	await process_frame
	check(landscape.get_global_rect().is_equal_approx(game.get_viewport_rect()), "landscape tracks the resized viewport")
	var point: Vector2 = game.board_transform() * game.center(game.sim.tiles[source])
	check(game.tile_at(point) == source, "scaled map hit testing matches rendering")
	await capture("map-narrow")
	game.reset_session()
	game.start_pve()
	await create_timer(0.15).timeout
	game.reset_session()
	await create_timer(1.5).timeout
	check(not game.board_visible and game.menu.visible and not game.transitioning, "reset cancels pending animation")
	check(game.menu.modulate.a == 1 and game.menu_slide == 0, "reset restores menu")
	root.content_scale_size = Vector2i(360, 640)
	root.size = Vector2i(360, 640)
	await process_frame
	game.update_layout()
	await process_frame
	for button in levels:
		check(game.get_viewport_rect().encloses(button.get_global_rect()), "difficulty button fits narrow menu")
	check(game.get_viewport_rect().encloses(game.menu.get_global_rect()), "complete narrow menu fits")
	await capture("ai-menu-narrow")
	print("Menu transition tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
