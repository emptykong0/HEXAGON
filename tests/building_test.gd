extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	test_collection()
	var model = Simulation.new()
	model.setup([1, 2], 123)
	model.tiles[0].owner = 1
	model.tiles[0].count = 9
	check(not model.build(1, 0, "command_tower"), "insufficient funds")
	model.tiles[0].count = 20
	check(not model.build(2, 0, "command_tower"), "foreign construction rejected")
	check(model.build(1, 0, "command_tower") and model.tiles[0].count == 10, "construction costs ten")
	check(not model.build(1, 0, "command_tower"), "one building per tile")
	check(model.attack_range(0) == 3, "tower range three")
	var targets: Array = []
	var far := -1
	for tile in model.tiles:
		if model.hex_distance(model.tiles[0], tile) == 3 and targets.size() < 3:
			tile.owner = 0
			tile.count = 15
			targets.append(tile.id)
		if model.hex_distance(model.tiles[0], tile) > 3: far = tile.id
	check(not model.set_targets(1, 0, [far]), "invalid target rejected")
	check(not model.set_targets(2, 0, targets), "foreign configuration rejected")
	check(model.set_targets(1, 0, targets), "configure three edge targets")
	model.tiles[0].count = 15
	for i in range(9): model.advance()
	check(model.fleets.is_empty(), "no premature dispatch")
	model.advance()
	check(model.fleets.size() == 1 and model.tiles[0].count == 15, "one second growth dispatched above reserve")
	var sent: Dictionary = {model.fleets[0].target: true}
	for batch in range(2):
		for i in range(10): model.advance()
		sent[model.fleets[-1].target] = true
	check(model.next_fleet_id == 4, "one fleet each second")
	check(sent.size() == 3, "remainder rotates across batches")
	var clone = Simulation.new()
	clone.restore(model.snapshot())
	for i in range(20):
		model.advance()
		clone.advance()
	check(model.snapshot() == clone.snapshot(), "orders and rotation survive snapshots")
	model.tiles[targets[0]].count = 0
	model.resolve_arrival(1, targets[0])
	check(model.building_at(0).targets.has(targets[0]), "capture preserves reinforcement target")
	check(model.set_targets(1, 0, targets), "friendly targets accepted")
	model.tiles[0].count = 14
	check(not model.dispatch(1, 0, [targets[0]]) and model.tiles[0].count == 14, "below reserve cannot dispatch or fabricate energy")
	model.tiles[0].count = 15
	check(not model.dispatch(1, 0, [targets[0]]), "exact reserve cannot dispatch")
	model.tiles[0].count = 20
	check(model.dispatch(1, 0, [targets[0]]) and model.tiles[0].count == 15 and model.fleets[-1].count == 5, "manual tower dispatch also preserves fifteen")
	model.tiles[0].count = 0
	model.resolve_arrival(2, 0)
	check(not model.building_at(0).is_empty() and model.building_at(0).targets.is_empty(), "capture retains building and clears orders")
	check(not model.demolish(1, 0), "former owner cannot demolish")
	model.tiles[0].count = 50
	check(model.demolish(2, 0) and model.tiles[0].count == 55, "demolition refunds five beyond growth cap")
	check(model.attack_range(0) == 2 and model.tiles[0].building_id == -1, "demolition restores ordinary tile")
	check(not model.demolish(2, 0), "cannot refund twice")
	model.finished = true
	check(not model.build(2, 0, "command_tower"), "finished match rejects construction")
	print("Building tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func test_collection() -> void:
	var model = Simulation.new()
	model.setup([1, 2], 123)
	model.tiles[0].owner = 1
	model.tiles[0].count = 20
	var neighbors: Array = []
	var outside := -1
	for tile in model.tiles:
		if model.hex_distance(model.tiles[0], tile) == 1:
			tile.owner = 1
			tile.count = 20
			neighbors.append(tile.id)
		elif model.hex_distance(model.tiles[0], tile) == 2:
			outside = tile.id
	check(neighbors.size() == 6, "six adjacent collection fixtures")
	model.tiles[outside].owner = 1
	model.tiles[outside].count = 50
	model.tiles[neighbors[0]].owner = 2
	model.tiles[neighbors[0]].count = 30
	model.tiles[neighbors[1]].owner = 0
	model.tiles[neighbors[1]].count = 30
	check(model.build(1, 0, "collection_tower") and model.tiles[0].count == 10, "collection tower costs ten")
	check(model.attack_range(0) == 2, "collection does not extend attack range")
	model.tick = 9
	model.advance_collection()
	check(model.tiles[0].count == 10, "collection waits one second")
	model.tick = 10
	model.advance_collection()
	check(model.tiles[0].count == 30, "collects four allied surpluses")
	for neighbor in neighbors.slice(2): check(model.tiles[neighbor].count == 15, "collection leaves fifteen")
	check(model.tiles[neighbors[0]].count == 30 and model.tiles[neighbors[1]].count == 30, "hostile and neutral energy untouched")
	check(model.tiles[outside].count == 50, "distance two excluded")
	model.tiles[0].count = 149
	for neighbor in neighbors.slice(2): model.tiles[neighbor].count = 16
	model.tick = 20
	model.advance_collection()
	var remaining := 0
	for neighbor in neighbors.slice(2): remaining += model.tiles[neighbor].count
	check(model.tiles[0].count == 150 and remaining == 63, "capacity clips transfer without deleting uncollected surplus")
	model.tiles[0].count = 160
	model.tick = 30
	model.advance_collection()
	check(model.tiles[0].count == 160, "over-cap reinforcement is not truncated")
	check(model.dispatch(1, 0, [neighbors[2]]) and model.tiles[0].count == 0, "collection tile supports ordinary full dispatch")
	model.tick = 40
	model.advance_collection()
	check(model.tiles[0].count == 3, "collection resumes after capacity freed")
	var clone = Simulation.new()
	clone.restore(model.snapshot())
	for i in range(30):
		model.advance()
		clone.advance()
	check(model.snapshot() == clone.snapshot(), "collection deterministic after snapshot")
	model.tiles[0].count = 0
	model.resolve_arrival(2, 0)
	model.tiles[neighbors[0]].count = 20
	model.tick = model.building_at(0).next_collection
	model.advance_collection()
	check(model.tiles[0].owner == 2 and model.tiles[0].count == 6 and model.tiles[neighbors[0]].count == 15, "captured collector serves new owner")
	check(model.demolish(2, 0) and model.tiles[0].count == 11, "collector refunds half cost")
	model.tiles[0].owner = 1
	model.tiles[0].count = 20
	model.build(1, 0, "collection_tower")
	model.tiles[neighbors[2]].count = 20
	model.build(1, neighbors[2], "collection_tower")
	var before := 0
	for tile in model.tiles: before += tile.count
	model.tick += 10
	model.advance_collection()
	var after := 0
	for tile in model.tiles: after += tile.count
	check(before == after, "overlapping collectors conserve all energy")
