extends SceneTree
var game: Node
var role := ""
var elapsed := 0.0
var stage := 0
var since_stage := 0.0
var fixture_ready := false
var target := -1
var extra_target := -1
var far := -1
var host_source := -1
var flight_ids: Dictionary = {}
var impact_ids: Dictionary = {}
var saw_orders := false
var saw_stop := false
var stopped_id := -1
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", role, " ", message)

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	call_deferred("setup")

func setup() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	if role == "host": game.host_game()
	else: game.join_game()

func find_tiles() -> void:
	target = -1
	extra_target = -1
	far = -1
	host_source = -1
	for tile in game.sim.tiles:
		var distance: int = game.sim.hex_distance(game.sim.tiles[0], tile)
		if distance == 2:
			if target < 0: target = tile.id
			elif extra_target < 0: extra_target = tile.id
		elif distance > 2:
			far = tile.id
		if tile.owner == 1: host_source = tile.id

func _process(delta: float) -> bool:
	elapsed += delta
	since_stage += delta
	if not is_instance_valid(game): return false
	if role == "host" and not game.active and game.players.size() == 2:
		game.start_network_game()
		game.sim.setup(game.roster, 123)
		for tile in game.sim.tiles:
			tile.owner = 0
			tile.count = 15
		find_tiles()
		game.sim.tiles[far].owner = 1
		game.sim.tiles[far].count = 40
		game.sim.build(1, far, "collection_tower")
		game.sim.tiles[0].owner = game.players[1]
		game.sim.tiles[0].count = 40
		game.sim.tiles[target].owner = game.players[1]
		game.sim.tiles[target].count = 50
		for tile in game.sim.tiles:
			if game.sim.hex_distance(game.sim.tiles[0], tile) == 1:
				tile.owner = game.players[1]
				tile.count = 30
		fixture_ready = true
	if game.active and not game.transitioning:
		find_tiles()
		for fleet in game.sim.fleets:
			if fleet.source == 0:
				if not flight_ids.has(fleet.id):
					check(fleet.target == target, "flight goes to configured single target")
				flight_ids[fleet.id] = true
		for hit in game.sim.impacts:
			if hit.source == 0: impact_ids[hit.id] = true
		var building: Dictionary = game.sim.building_at(0)
		if not building.get("targets", []).is_empty(): saw_orders = true
		if saw_orders and building.get("targets", []).is_empty(): saw_stop = true
		if role == "client":
			if stage == 0 and game.sim.tiles[0].owner == game.local_player():
				game.submit_building_command("build_collection", 0, [])
				stage = 1
			elif stage == 1 and building.get("type", "") == "collection_tower":
				game.submit_building_command("targets", 0, [target, extra_target])
				game.submit_building_command("targets", 0, [far])
				game.submit_building_command("targets", host_source, [target])
				stage = 2
				since_stage = 0
			elif stage == 2 and since_stage > 0.4:
				check(building.targets.is_empty(), "host rejects multiple and distant targets")
				check(game.sim.building_at(host_source).targets.is_empty(), "host rejects foreign configuration")
				game.submit_building_command("targets", 0, [target])
				stage = 3
			elif stage == 3 and building.get("targets", []) == [target]:
				since_stage = 0
				stage = 4
			elif stage == 4 and since_stage > 2.6:
				check(flight_ids.size() >= 2 and impact_ids.size() >= 1, "client observes repeated flights and whole-batch arrival")
				game.submit_building_command("stop", 0, [])
				stage = 5
			elif stage == 5 and building.targets.is_empty():
				stopped_id = game.sim.next_fleet_id
				since_stage = 0
				stage = 6
			elif stage == 6 and since_stage > 1.3:
				check(game.sim.next_fleet_id == stopped_id and game.sim.tiles[0].count > 0, "stop synchronizes while collection continues")
				print("Collection transport network client: ", "PASS" if failures == 0 else "FAIL")
				quit(0 if failures == 0 else 1)
		elif elapsed > 8 and game.multiplayer.get_peers().is_empty():
			check(fixture_ready and saw_orders and saw_stop and flight_ids.size() >= 2 and impact_ids.size() >= 1, "host observes configuration, recurring transport and stop")
			check(game.sim.building_at(host_source).targets.is_empty(), "foreign order did not modify host tower")
			print("Collection transport network host: ", "PASS" if failures == 0 else "FAIL")
			quit(0 if failures == 0 else 1)
	if elapsed > 20:
		printerr("Collection transport network timeout: ", role, " stage=", stage, " stage_age=", since_stage)
		quit(1)
	return false
