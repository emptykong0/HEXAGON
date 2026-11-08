extends SceneTree
var game: Node
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func capture(name: String) -> void:
	game.queue_redraw()
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.resize(1440, int(1440.0 * picture.get_height() / picture.get_width()))
		picture.save_png("res://test-results/" + name + ".png")
func key(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)
	event.pressed = false
	event.echo = false
	root.push_input(event, true)
	await process_frame
func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame
func check_layout() -> void:
	var area: Rect2 = game.board_area()
	var transform: Transform2D = game.board_transform()
	var panel: Rect2 = game.operations.get_global_rect()
	for tile in game.sim.tiles:
		for vertex in game.hex_polygon(game.center(tile), game.HEX_SIZE):
			var point: Vector2 = transform * vertex
			check(area.grow(1).has_point(point), "complete map stays in board area")
			check(not panel.has_point(point), "operations do not cover a tile")
		check(game.tile_at(transform * game.center(tile)) == tile.id, "scaled tile hit testing")
	check(game.get_viewport_rect().encloses(panel), "entire operations panel fits the viewport")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.tutorial.show()
	await capture("tutorial-page")
	game.tutorial.hide()
	game.start_pve()
	await create_timer(1.6).timeout
	game.set_process(false)
	var source := 0
	game.sim.tiles[source].owner = 1
	game.sim.tiles[source].count = 20
	var stable_transform: Transform2D = game.board_transform()
	await click_at(game.board_transform() * game.center(game.sim.tiles[source]))
	game.update_operations()
	await create_timer(0.2).timeout
	check(game.operations.visible and game.selected == source, "selection opens side operations")
	check(stable_transform == game.board_transform(), "selection does not move map")
	check_layout()
	await capture("build-operations")
	var build_button: Button = game.operations.buttons.build
	await click_at(build_button.get_global_rect().get_center())
	check(game.sim.tiles[source].count == 10 and not game.sim.building_at(source).is_empty(), "GUI button constructs and consumes ten")
	check(game.sim.fleets.is_empty(), "GUI button does not dispatch")
	game.update_operations()
	await create_timer(0.2).timeout
	await capture("command-operations")
	await key(KEY_DELETE)
	check(not game.sim.building_at(source).is_empty(), "Delete does not demolish")
	await key(KEY_Q, true)
	check(not game.editing_targets, "key repeat ignored")
	await key(KEY_Q)
	check(game.editing_targets, "Q starts target editing")
	var path: Array = []
	for direction in game.sim.HEX_NEIGHBORS:
		var candidate: Array = []
		for distance in range(1, 4):
			for tile in game.sim.tiles:
				if Vector2i(tile.q, tile.r) == Vector2i(game.sim.tiles[source].q, game.sim.tiles[source].r) + direction * distance:
					candidate.append(tile.id)
		if candidate.size() == 3:
			path = candidate
			break
	check(path.size() == 3, "three contiguous painting fixtures")
	game.sim.tiles[path[0]].owner = 1
	game.sim.tiles[path[1]].owner = -1
	game.sim.tiles[path[2]].owner = 0
	await stroke(path[0], path[2], MOUSE_BUTTON_LEFT)
	check(game.pending_targets.size() == 3 and game.sim.fleets.is_empty(), "left drag samples skipped cells across all factions")
	await stroke(path[0], path[2], MOUSE_BUTTON_RIGHT)
	check(game.pending_targets.is_empty() and game.editing_targets, "right drag removes without leaving edit mode")
	await stroke(path[0], path[2], MOUSE_BUTTON_LEFT)
	game.update_operations()
	await capture("target-operations")
	await key(KEY_R)
	check(game.sim.building_at(source).targets.size() == 3, "R saves targets")
	await key(KEY_Q)
	game.pending_targets.clear()
	await key(KEY_F)
	check(not game.editing_targets and game.sim.building_at(source).targets.size() == 3, "F cancels edit and preserves orders")
	await key(KEY_W)
	check(game.sim.building_at(source).targets.is_empty(), "W stops automatic dispatch")
	await key(KEY_E)
	check(game.sim.tiles[source].count == 15 and game.sim.building_at(source).is_empty(), "E demolishes and refunds five")
	await key(KEY_W)
	check(game.sim.building_at(source).get("type", "") == "collection_tower" and game.sim.tiles[source].count == 5, "W builds collector")
	game.update_operations()
	await capture("collection-operations")
	check(game.operations.buttons.has("targets") and game.operations.buttons.stop.disabled, "collector exposes target setting and disabled stop")
	await key(KEY_A, true)
	check(not game.editing_targets, "collector target shortcut ignores key repeat")
	await key(KEY_A)
	check(game.editing_targets, "A enters collector target editing")
	await click_at(game.board_transform() * game.center(game.sim.tiles[path[0]]))
	await click_at(game.board_transform() * game.center(game.sim.tiles[path[1]]))
	check(game.pending_targets == [path[1]], "collector click replaces its single target")
	await click_at(game.board_transform() * game.center(game.sim.tiles[path[2]]))
	check(game.pending_targets == [path[1]], "collector ignores out-of-range target")
	await stroke(path[1], path[1], MOUSE_BUTTON_RIGHT)
	check(game.editing_targets and game.pending_targets.is_empty(), "right click removes collector target without leaving edit")
	await stroke(path[0], path[1], MOUSE_BUTTON_LEFT)
	check(game.pending_targets.size() == 1 and game.pending_targets[0] == path[1], "collector painting keeps just the latest valid target")
	await key(KEY_R)
	check(game.sim.building_at(source).targets == [path[1]] and not game.operations.buttons.stop.disabled, "R saves one collector target")
	check(game.operations.stats.text.contains("目标 1 / 1"), "collector shows single-target capacity")
	await capture("collection-transport-operations")
	await key(KEY_A)
	await click_at(game.board_transform() * game.center(game.sim.tiles[path[0]]))
	await key(KEY_F)
	check(game.sim.building_at(source).targets == [path[1]], "F preserves collector's saved order")
	await click_at(game.operations.buttons.stop.get_global_rect().get_center())
	check(game.sim.building_at(source).targets.is_empty() and game.sim.fleets.is_empty(), "stop button clears configuration without dispatch")
	await key(KEY_A)
	await click_at(game.board_transform() * game.center(game.sim.tiles[path[0]]))
	await key(KEY_R)
	await key(KEY_W)
	check(game.sim.building_at(source).targets.is_empty(), "W stops collector transport")
	check(game.operations.buttons.upgrade.disabled, "upgrade disabled below twenty")
	await key(KEY_Q)
	check(game.sim.building_at(source).level == 1 and game.sim.tiles[source].count == 5, "disabled shortcut does not charge")
	game.sim.tiles[source].count = 40
	await key(KEY_Q)
	check(game.sim.building_at(source).level == 2 and game.sim.tiles[source].count == 20, "Q upgrades collector")
	check(game.operations.stats.text.contains("500") and game.operations.stats.text.contains("收集 2 格"), "upgraded stats show capacity and radius")
	check(game.operations.buttons.upgrade.disabled, "max level upgrade disabled")
	await key(KEY_Q)
	check(game.sim.tiles[source].count == 20, "max level shortcut cannot charge twice")
	await capture("upgraded-collection-operations")
	for viewport_size in [Vector2i(900, 700), Vector2i(800, 1000)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		game.update_layout()
		await process_frame
		check_layout()
		await capture("collection-transport-%sx%s" % [viewport_size.x, viewport_size.y])
	await key(KEY_E)
	check(game.sim.building_at(source).is_empty() and game.sim.tiles[source].count == 35, "E refunds upgraded investment")
	game.sim.tiles[source].count = 9
	await key(KEY_Q)
	check(game.sim.building_at(source).is_empty(), "disabled build also rejects shortcut")
	game.sim.tiles[source].count = 20
	var field := LineEdit.new()
	root.add_child(field)
	field.grab_focus()
	await key(KEY_Q)
	check(game.sim.building_at(source).is_empty(), "text input suppresses shortcuts")
	field.queue_free()
	await process_frame
	for viewport_size in [Vector2i(900, 700), Vector2i(1600, 900), Vector2i(800, 1000)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		await process_frame
		game.update_layout()
		await process_frame
		check_layout()
		await capture("operations-%sx%s" % [viewport_size.x, viewport_size.y])
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	cancel.position = game.operations.buttons.build.get_global_rect().get_center()
	root.push_input(cancel, true)
	await process_frame
	check(game.selected == -1, "right click cancels even over operations")
	await click_at(game.board_transform() * game.center(game.sim.tiles[source]))
	game.update_operations()
	await key(KEY_F)
	check(game.selected == -1 and not game.operations.visible, "F cancels selection")
	game.selected = source
	game.sim.finished = true
	await key(KEY_Q)
	check(game.sim.building_at(source).is_empty(), "finished match rejects shortcuts")
	game.reset_session()
	check(not game.operations.visible and not game.editing_targets, "reset clears operations")
	print("Building UI tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func stroke(first: int, last: int, button: int) -> void:
	var start: Vector2 = game.board_transform() * game.center(game.sim.tiles[first])
	var finish: Vector2 = game.board_transform() * game.center(game.sim.tiles[last])
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = start
	root.push_input(press, true)
	await process_frame
	for point in [finish, start, finish]:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		root.push_input(motion, true)
		await process_frame
	press.pressed = false
	press.position = finish
	root.push_input(press, true)
	await process_frame
	check(not game.target_painting, "release ends brush stroke")
