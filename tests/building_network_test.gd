extends SceneTree
var game: Node
var role := ""
var elapsed := 0.0
var stage := 0
var fixture_ready := false
var saw_command := false
var saw_orders := false
var saw_flight := false
var saw_collection := false
var saw_upgrade := false
var source := -1
var donor := -1
func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	call_deferred("setup")
func setup() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if role == "host": game.host_game()
	else: game.join_game()
func _process(delta: float) -> bool:
	elapsed += delta
	if not is_instance_valid(game): return false
	if role == "host" and not game.active and game.players.size() == 2: game.start_network_game()
	if role == "host" and game.active and not fixture_ready:
		for tile in game.sim.tiles:
			if tile.owner != 0 and tile.owner != 1: source = tile.id
		game.sim.tiles[source].count = 40
		for tile in game.sim.tiles:
			if tile.owner == 0 and game.sim.hex_distance(game.sim.tiles[source], tile) == 1:
				tile.owner = game.sim.tiles[source].owner
				tile.count = 35
				donor = tile.id
				break
		fixture_ready = true
	if game.active and not game.transitioning:
		if role == "host":
			for building in game.sim.buildings:
				if building.type == "command_tower":
					saw_command = true
					if not building.targets.is_empty(): saw_orders = true
				if building.type == "collection_tower" and game.sim.tiles[donor].count == 15 and game.sim.tiles[source].count > 15:
					saw_collection = true
				if building.get("level", 1) == 2: saw_upgrade = true
			if not game.sim.fleets.is_empty(): saw_flight = true
			if elapsed > 12:
				var ok: bool = saw_command and saw_orders and saw_flight and saw_collection and saw_upgrade and game.sim.buildings.is_empty()
				print("Building network host: ", "PASS" if ok else "FAIL", " collected=", saw_collection)
				quit(0 if ok else 1)
		else:
			if stage == 0:
				for tile in game.sim.tiles:
					if tile.owner == game.local_player() and tile.count > 35: source = tile.id
					if tile.owner == 1: game.request_building_command.rpc_id(1, "build_collection", tile.id, [])
				if source < 0: return false
				game.submit_building_command("build", source, [])
				stage = 1
			elif stage == 1 and not game.sim.building_at(source).is_empty():
				var targets: Array = []
				for tile in game.sim.tiles:
					if tile.id != source and game.sim.in_range(source, tile.id) and targets.size() < 2: targets.append(tile.id)
				game.submit_building_command("targets", source, targets)
				stage = 2
			elif stage == 2 and elapsed > 6:
				game.submit_building_command("demolish", source, [])
				stage = 3
			elif stage == 3 and game.sim.building_at(source).is_empty():
				game.submit_building_command("build_collection", source, [])
				stage = 4
			elif stage == 4 and elapsed > 8 and game.sim.tiles[source].count >= 20:
				game.submit_building_command("upgrade", source, [])
				stage = 5
			elif stage == 5 and elapsed > 9 and game.sim.building_at(source).get("level", 1) == 2:
				saw_upgrade = game.sim.collection_settings(source).storage_cap == 500
				saw_collection = true
				game.submit_building_command("demolish", source, [])
				stage = 6
			elif stage == 6 and elapsed > 11:
				var ok: bool = saw_collection and saw_upgrade and game.sim.buildings.is_empty() and game.sim.attack_range(source) == 2 and game.sim.next_fleet_id > 1
				print("Building network client: ", "PASS" if ok else "FAIL")
				quit(0 if ok else 1)
	if elapsed > 20:
		printerr("Building network timeout")
		quit(1)
	return false
