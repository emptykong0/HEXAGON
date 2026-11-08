extends SceneTree
var failures := 0
var game: Node

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func mouse(tile: int, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = game.get_global_transform_with_canvas() * (game.board_transform() * game.center(game.sim.tiles[tile]) if tile >= 0 else Vector2(1200, 780))
	game._unhandled_input(event)

func click(tile: int) -> void:
	mouse(tile, true)
	mouse(tile, false)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.start_pve()
	await create_timer(1.6).timeout
	game.set_process(false)
	var source := -1
	var enemy := -1
	var neutral := -1
	for tile in game.sim.tiles:
		if tile.owner == 1: source = tile.id
		if tile.owner == -1: enemy = tile.id
		if tile.owner == 0: neutral = tile.id
	for tile in game.sim.tiles:
		if tile.owner == 0 and game.sim.in_range(source, tile.id):
			enemy = tile.id
			game.sim.tiles[enemy].owner = -1
			break
	for tile in game.sim.tiles:
		if tile.owner == 0 and game.sim.in_range(source, tile.id):
			neutral = tile.id
			break
	click(enemy)
	check(game.selected == -1 and game.sim.fleets.is_empty(), "enemy cannot be selected as source")
	click(source)
	check(game.selected == source and game.sim.fleets.is_empty(), "first click selects without dispatch")
	check(game.range_tile == source, "click displays source range")
	click(source)
	check(game.selected == source and game.sim.fleets.is_empty(), "clicking same source does not dispatch")
	click(enemy)
	check(game.selected == -1 and game.sim.fleets.size() == 1 and game.sim.fleets[0].source == source and game.sim.fleets[0].target == enemy, "second click attacks exactly once")
	check(game.sim.tiles[source].count == 0, "click dispatch sends all troops")
	game.sim.tiles[source].count = 12
	click(source)
	mouse(source, true, MOUSE_BUTTON_RIGHT)
	click(neutral)
	check(game.selected == -1 and game.sim.fleets.size() == 1, "right click cancels selection")
	mouse(source, true)
	mouse(neutral, false)
	check(game.sim.fleets.size() == 2 and game.sim.fleets[-1].target == neutral and game.selected == -1, "drag remains supported")
	game.sim.tiles[source].count = 11
	mouse(source, true)
	mouse(source, true, MOUSE_BUTTON_RIGHT)
	mouse(enemy, false)
	check(game.sim.fleets.size() == 2 and game.sim.tiles[source].count == 11, "right click cancels active drag")
	game.sim.tiles[neutral].owner = 1
	click(source)
	click(neutral)
	check(game.sim.fleets.size() == 3 and game.sim.fleets[-1].target == neutral, "click dispatch supports friendly reinforcement")
	game.sim.tiles[source].count = 10
	click(source)
	game.sim.tiles[source].owner = -1
	click(enemy)
	check(game.sim.fleets.size() == 3, "captured source cannot send after selection")
	game.sim.tiles[source].owner = 1
	click(source)
	game.reset_session()
	check(game.selected == -1 and game.dragged == -1, "reset clears input state")
	print("Input tests: ", "PASS" if failures == 0 else "FAIL (%s)" % failures)
	quit(0 if failures == 0 else 1)
