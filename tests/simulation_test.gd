extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	test_random_maps()
	test_opening_choices()
	test_growth_cap()
	test_outcomes()
	test_ranges()
	var sim = Simulation.new()
	sim.setup([1, 2])
	check(sim.tiles.size() == Simulation.MAP_TILE_COUNT, "configured map size")
	var source := -1
	var enemy := -1
	for tile in sim.tiles:
		if tile.owner == 1: source = tile.id
		if tile.owner == 2: enemy = tile.id
	sim.tiles[source].attack_range = 20
	check(not sim.dispatch(2, source, [enemy]), "reject foreign source")
	check(not sim.dispatch(1, source, [enemy, enemy]), "reject duplicate targets atomically")
	check(sim.tiles[source].count == 20, "invalid command preserves troops")
	check(sim.dispatch(1, source, [enemy]), "valid dispatch")
	check(sim.tiles[source].count == 0 and sim.tiles[source].owner == 1, "empty origin retains ownership")
	sim.tiles[enemy].count = 2
	sim.resolve_arrival(1, enemy)
	check(sim.tiles[enemy].owner == 2 and sim.tiles[enemy].count == 1, "first hostile arrival")
	sim.resolve_arrival(1, enemy)
	check(sim.tiles[enemy].owner == 1 and sim.tiles[enemy].count == 0, "last hit captures at zero")
	sim.resolve_arrival(1, enemy)
	check(sim.tiles[enemy].count == 1, "remaining arrivals reinforce")
	sim.tiles[enemy].count = 0
	sim.resolve_arrival(2, enemy)
	check(sim.tiles[enemy].owner == 2 and sim.tiles[enemy].count == 1, "capture empty tile retains one")
	for tile in sim.tiles:
		if tile.owner == 0:
			tile.owner = 1
			break
	sim.tiles[source].owner = 2
	check(sim.fleets[0].owner == 1, "in-flight owner independent of origin")
	var clone = Simulation.new()
	clone.restore(sim.snapshot())
	for i in range(70):
		sim.advance()
		clone.advance()
	check(sim.snapshot() == clone.snapshot(), "snapshot restores deterministic progress")
	sim.tiles[source].owner = 1
	sim.tiles[source].count = 7
	var extra_target: int = (enemy + 1) % sim.tiles.size()
	while extra_target == source or extra_target == enemy:
		extra_target = (extra_target + 1) % sim.tiles.size()
	check(sim.dispatch(1, source, [enemy, extra_target]), "multi-target extension")
	var last: Dictionary = sim.fleets[-1]
	var previous: Dictionary = sim.fleets[-2]
	check(last.count + previous.count == 7, "allocation conserves troops")
	print("Simulation tests: ", "PASS" if failures == 0 else "FAIL (%s)" % failures)
	quit(0 if failures == 0 else 1)

func test_random_maps() -> void:
	var shapes: Dictionary = {}
	for seed_value in range(100):
		var model = Simulation.new()
		model.setup([1, 2, 3, 4], seed_value)
		var positions: Dictionary = {}
		var owners: Dictionary = {}
		for tile in model.tiles:
			positions[Vector2i(tile.q, tile.r)] = true
			if tile.owner != 0:
				owners[tile.owner] = true
			check(absi(tile.r) <= Simulation.MAP_R_RADIUS and absi(tile.q) <= Simulation.MAP_Q_RADIUS and absi(tile.q + tile.r) <= Simulation.MAP_Q_RADIUS, "map within screen bounds")
		check(positions.size() == Simulation.MAP_TILE_COUNT and owners.size() == 4, "unique cells and four homes")
		var reached: Dictionary = {Vector2i.ZERO: true}
		var pending: Array[Vector2i] = [Vector2i.ZERO]
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			for direction in Simulation.HEX_NEIGHBORS:
				var neighbor: Vector2i = cell + direction
				if positions.has(neighbor) and not reached.has(neighbor):
					reached[neighbor] = true
					pending.append(neighbor)
		check(reached.size() == Simulation.MAP_TILE_COUNT, "connected map")
		# Canonical occupancy key detects different shapes, not just cell ordering.
		var shape := ""
		for q in range(-Simulation.MAP_Q_RADIUS, Simulation.MAP_Q_RADIUS + 1):
			for r in range(-Simulation.MAP_R_RADIUS, Simulation.MAP_R_RADIUS + 1):
				shape += "1" if positions.has(Vector2i(q, r)) else "0"
		shapes[shape] = true
		var repeated = Simulation.new()
		repeated.setup([1, 2, 3, 4], seed_value)
		check(model.snapshot() == repeated.snapshot(), "seed reproducibility")
	check(shapes.size() > 90, "varied random silhouettes")

func test_growth_cap() -> void:
	var model = Simulation.new()
	model.setup([1, 2], 123)
	for i in range(400):
		model.advance()
	var neutral := -1
	for tile in model.tiles:
		if tile.owner == 0:
			check(tile.count == 15, "neutral stops at fifteen")
			neutral = tile.id
		else:
			check(tile.count == 50, "owned stops at fifty")
	model.tiles[neutral].count = 14
	for i in range(10): model.advance()
	check(model.tiles[neutral].count == 15, "fourteen reaches fifteen")
	model.tiles[neutral].count = 16
	for i in range(10): model.advance()
	check(model.tiles[neutral].count == 16, "cap does not erase existing units")
	model.tiles[neutral].owner = 1
	for i in range(10): model.advance()
	check(model.tiles[neutral].count == 17, "captured tile grows past cap")
	model.tiles[neutral].count = 49
	for i in range(10): model.advance()
	check(model.tiles[neutral].count == 50, "owned forty-nine reaches fifty")
	model.resolve_arrival(1, neutral)
	check(model.tiles[neutral].count == 51, "reinforcement can exceed growth cap")
	for i in range(10): model.advance()
	check(model.tiles[neutral].count == 51, "over-cap units preserved without growth")

func test_opening_choices() -> void:
	# Bounds for this reproducible map sample, not a constraint on every random map.
	for seats in [2, 3, 4]:
		for map_seed in range(1, 17):
			var model = Simulation.new()
			model.setup([1, 2, 3, 4].slice(0, seats), map_seed)
			var counts: Array[int] = []
			for home in model.tiles:
				if home.owner == 0:
					continue
				var choices := 0
				for tile in model.tiles:
					var distance: int = model.hex_distance(home, tile)
					if tile.owner == 0 and distance <= Simulation.DEFAULT_ATTACK_RANGE:
						choices += 1
					if tile.owner != 0 and tile.id != home.id:
						check(distance >= 5, "opening ranges stay separated in reference maps")
				counts.append(choices)
			check(counts.max() - counts.min() <= [2, 2, 4][seats - 2], "bounded opening-choice spread in reference maps")

func test_outcomes() -> void:
	var model = Simulation.new()
	model.setup([1, 2, 3], 456)
	for tile in model.tiles: tile.attack_range = 20
	var homes: Dictionary = {}
	for tile in model.tiles:
		if tile.owner != 0:
			homes[tile.owner] = tile.id
	model.dispatch(1, homes[1], [homes[2]])
	model.evaluate_outcome()
	check(not model.finished and model.result_for(1) == "", "dispatching all units does not lose")
	model.dispatch(2, homes[2], [homes[1]])
	model.resolve_arrival(1, homes[2])
	model.evaluate_outcome()
	check(model.result_for(2) == "失败" and not model.finished, "one eliminated player does not end multiplayer match")
	check(not model.dispatch(2, homes[2], [homes[1]]), "eliminated player cannot command")
	check(not model.fleets.any(func(f): return f.owner == 2), "eliminated fleets removed")
	var previous_owner: int = model.tiles[homes[1]].owner
	model.resolve_arrival(2, homes[1])
	check(model.tiles[homes[1]].owner == previous_owner, "eliminated player cannot recapture")
	model.tiles[homes[3]].count = 1
	model.resolve_arrival(1, homes[3])
	model.evaluate_outcome()
	check(model.finished and model.winner == 1, "last opponent captured ends match")
	check(model.result_for(1) == "胜利" and model.result_for(3) == "失败", "per-player results")
	check(model.tiles.any(func(t): return t.owner == 0), "neutral territory does not block victory")
	var restored = Simulation.new()
	restored.restore(model.snapshot())
	check(restored.result_for(1) == "胜利" and restored.result_for(2) == "失败", "snapshot retains results")
	var frozen: Dictionary = model.snapshot()
	model.advance()
	check(model.snapshot() == frozen, "finished match freezes simulation")
	check(not model.dispatch(1, homes[2], [homes[1]]), "finished match rejects commands")
	model.setup([1, 2], 456)
	check(not model.finished and model.eliminated.is_empty() and model.winner == 0, "new match clears previous result")
	var pve = Simulation.new()
	pve.setup([1, -1], 789)
	for tile in pve.tiles:
		if tile.owner == 1:
			tile.owner = -1
	pve.evaluate_outcome()
	check(pve.result_for(1) == "失败" and pve.result_for(-1) == "胜利", "PVE defeat uses same rules")

func test_ranges() -> void:
	var model = Simulation.new()
	model.setup([1, 2], 123)
	var source := 0
	model.tiles[source].owner = 1
	model.tiles[source].count = 20
	var edge := -1
	var outside := -1
	for tile in model.tiles:
		var distance: int = model.hex_distance(model.tiles[source], tile)
		if distance == 2: edge = tile.id
		if distance == 3: outside = tile.id
	check(edge >= 0 and outside >= 0, "range boundary fixtures")
	check(model.attack_range(source) == 2, "default radius two")
	check(not model.dispatch(1, source, [outside]), "host rejects beyond range")
	check(not model.dispatch(1, source, [edge, outside]) and model.tiles[source].count == 20, "multi target range validation is atomic")
	check(model.dispatch(1, source, [edge]), "distance two included")
	model.tiles[source].count = 20
	model.tiles[source].building_id = 77
	model.buildings.append({"id": 77, "type": "barracks", "attack_range": 5})
	check(model.attack_range(source) == 5 and model.dispatch(1, source, [outside]), "building instance overrides range")
	var clone = Simulation.new()
	clone.restore(model.snapshot())
	check(clone.attack_range(source) == 5, "network state retains building range")
