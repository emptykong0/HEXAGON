extends SceneTree
var game: Node
var role := ""
var acted := false
var elapsed := 0.0
var running := 0.0
var started := false
var prepared_finish := false

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	call_deferred("setup")

func setup() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if role == "host":
		game.host_game()
	else:
		game.address.text = "127.0.0.1"
		game.join_game()

func _process(delta: float) -> bool:
	elapsed += delta
	if not is_instance_valid(game): return false
	if role == "host" and not started and game.players.size() == 3:
		game.start_network_game()
		started = true
	if game.active:
		running += delta
		if role == "host" and game.sim.next_fleet_id == 3 and game.sim.fleets.is_empty() and not prepared_finish:
			# Apply the final captures after both real volleys land. The host
			# evaluates elimination after all arrivals on a tick.
			for tile in game.sim.tiles:
				if tile.owner != 0 and tile.owner != 1:
					game.sim.resolve_impact(1, tile.id, maxi(1, tile.count))
			prepared_finish = true
		if role != "host" and not acted and not game.transitioning:
			var source := -1
			var target := -1
			for tile in game.sim.tiles:
				if tile.owner == game.local_player(): source = tile.id
				if tile.owner == 0: target = tile.id
			for tile in game.sim.tiles:
				if tile.owner == 0 and game.sim.in_range(source, tile.id):
					target = tile.id
					break
			for tile in game.sim.tiles:
				if not game.sim.in_range(source, tile.id):
					game.request_dispatch.rpc_id(1, source, tile.id)
					break
			if role == "client1":
				mouse(source, true)
				mouse(source, false)
				mouse(target, true)
				mouse(target, false)
			else:
				mouse(source, true)
				mouse(target, false)
			acted = true
		if running > (3.5 if role == "client1" else 4.2) and role != "host":
			var valid: bool = game.sim.finished and game.sim.winner == 1 and game.sim.result_for(game.local_player()) == "失败" and game.result_label.text == "失败" and not game.victory_screen.visible and game.sim.next_fleet_id == 3
			print("NETWORK ", role, ": ", "PASS" if valid else "FAIL", " tick=", game.sim.tick, " result=", game.result_label.text)
			quit(0 if valid else 1)
		if role == "host" and running > 5.0:
			var valid: bool = game.sim.next_fleet_id == 3 and game.sim.finished and game.result_label.text == "胜利" and game.victory_screen.visible and not game.result_label.visible
			print("NETWORK host: ", "PASS" if valid else "FAIL")
			quit(0 if valid else 1)
	if elapsed > 15:
		printerr("NETWORK timeout: ", role)
		quit(1)
	return false

func mouse(tile: int, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = game.get_global_transform_with_canvas() * (game.board_transform() * game.center(game.sim.tiles[tile]))
	game._unhandled_input(event)
