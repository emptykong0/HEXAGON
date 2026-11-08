extends SceneTree
var game: Node
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://test-results/victory-" + label + ".png")

func finish_for(owner: int) -> void:
	for tile in game.sim.tiles:
		if tile.owner != 0: tile.owner = owner
	game.sim.evaluate_outcome()

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1280, 820)
	root.size = Vector2i(1280, 820)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(not game.victory_screen.visible, "page stays hidden at startup")
	game.start_pve()
	await create_timer(1.65).timeout
	finish_for(1)
	await process_frame
	await process_frame
	check(game.victory_screen.visible and not game.hud.visible and not game.result_label.visible, "victory opens a dedicated page and hides match UI")
	check(game.result_label.text == "胜利" and not game.operations.visible, "existing result state preserved and operations closed")
	var finished_state: Dictionary = game.sim.snapshot()
	await create_timer(0.18).timeout
	await capture("entrance")
	await create_timer(0.65).timeout
	check(game.victory_screen.reveal == 1.0 and not game.victory_screen.return_button.disabled, "entrance completes once without restarting each frame")
	check(game.sim.snapshot() == finished_state, "presentation leaves the finished simulation frozen")
	check(game.victory_screen.return_button.has_focus(), "primary action receives keyboard focus")
	check(game.victory_screen.quit_requested.is_connected(game.quit_game), "quit action uses the game's existing exit path")
	await capture("page")
	for viewport_size in [Vector2i(1600,900), Vector2i(900,700), Vector2i(800,1000), Vector2i(360,640)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		await process_frame
		var page: Control = game.victory_screen
		var bounds: Rect2 = game.get_viewport_rect()
		check(bounds.encloses(page.return_button.get_global_rect()) and bounds.encloses(page.quit_button.get_global_rect()), "buttons fit viewport %s" % viewport_size)
		check(not page.return_button.get_global_rect().intersects(page.quit_button.get_global_rect()), "buttons do not overlap")
		check(bounds.encloses(page.heading.get_global_rect()), "title fits viewport")
		await capture("%sx%s" % [viewport_size.x,viewport_size.y])
	await click_at(game.victory_screen.return_button.get_global_rect().get_center())
	check(not game.active and game.menu.visible and not game.victory_screen.visible, "return button restores homepage")
	game.start_pve()
	await create_timer(1.65).timeout
	finish_for(-1)
	await process_frame
	await process_frame
	check(game.result_label.text == "失败" and game.result_label.visible and not game.victory_screen.visible, "defeated local player cannot see the victory page")
	game.reset_session()
	game.start_pve()
	finish_for(1)
	await process_frame
	game.reset_session()
	await create_timer(0.8).timeout
	check(not game.victory_screen.visible and game.menu.visible and game.result_label.visible, "reset cancels pending result animation")
	print("Victory screen tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
