extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func total(model) -> int:
	var result := 0
	for tile in model.tiles: result += tile.count
	return result
func _initialize() -> void:
	var model = Simulation.new()
	model.setup([1, 2], 123)
	for tile in model.tiles:
		if model.hex_distance(model.tiles[0], tile) <= 3:
			tile.owner = 1
			tile.count = 15
	model.tiles[0].count = 30
	check(model.build(1, 0, "collection_tower"), "build collector fixture")
	var adjacent: Array = []
	var ring_two: Array = []
	var outside := -1
	for tile in model.tiles:
		var distance: int = model.hex_distance(model.tiles[0], tile)
		if distance == 1: adjacent.append(tile.id)
		if distance == 2: ring_two.append(tile.id)
		if distance == 3: outside = tile.id
	check(adjacent.size() == 6 and ring_two.size() > 2, "range fixtures")
	var command: int = adjacent[0]
	var collector: int = adjacent[1]
	model.tiles[command].count = 60
	model.build(1, command, "command_tower")
	model.tiles[collector].count = 110
	model.build(1, collector, "collection_tower")
	model.tick = 10
	model.advance_collection()
	check(model.tiles[command].count == 50 and model.tiles[collector].count == 100, "base collector excludes command and collection towers")
	check(not model.upgrade(2, 0), "foreign upgrade rejected")
	check(not model.upgrade(1, command), "command tower cannot upgrade")
	check(not model.upgrade(1, ring_two[0]), "empty tile cannot upgrade")
	model.tiles[0].count = 19
	var before: Dictionary = model.snapshot()
	check(not model.upgrade(1, 0) and model.snapshot() == before, "insufficient upgrade is atomic")
	model.tiles[0].count = 40
	check(model.upgrade(1, 0) and model.tiles[0].count == 20 and model.building_at(0).level == 2, "upgrade costs twenty from local tile")
	check(model.collection_settings(0).storage_cap == 500 and model.collection_settings(0).radius == 2, "upgraded capacity and range")
	before = model.snapshot()
	check(not model.upgrade(1, 0) and model.snapshot() == before, "only one upgrade and no double charge")
	var donor: int = ring_two[0]
	var excluded_command: int = ring_two[1]
	var excluded_collector: int = ring_two[2]
	model.tiles[excluded_command].count = 60
	model.build(1, excluded_command, "command_tower")
	model.tiles[excluded_collector].count = 110
	model.build(1, excluded_collector, "collection_tower")
	# Freeze the other collectors, isolating this tower's transfer result.
	for building in model.buildings:
		if building.tile != 0: building.next_collection = 9999
	model.tiles[donor].count = 50
	model.tiles[outside].count = 50
	model.tick = 20
	var energy_before := total(model)
	model.advance_collection()
	check(model.tiles[0].count == 55 and model.tiles[donor].count == 15, "radius-two edge collects and preserves fifteen")
	check(model.tiles[outside].count == 50, "radius three excluded")
	check(model.tiles[command].count == 50 and model.tiles[collector].count == 100 and model.tiles[excluded_command].count == 50 and model.tiles[excluded_collector].count == 100, "upgraded collection excludes both tower types at all distances")
	check(total(model) == energy_before, "collection conserves energy")
	model.tiles[0].count = 499
	model.tiles[donor].count = 20
	model.tick = 30
	model.advance_collection()
	check(model.tiles[0].count == 500 and model.tiles[donor].count == 19, "five hundred cap leaves remainder at source")
	model.tiles[0].count = 510
	model.tick = 40
	model.advance_collection()
	check(model.tiles[0].count == 510, "over-cap units preserved")
	var clone = Simulation.new()
	clone.restore(model.snapshot())
	for i in range(20):
		model.advance()
		clone.advance()
	check(model.snapshot() == clone.snapshot() and clone.collection_settings(0).storage_cap == 500, "upgrade survives snapshot and deterministic progress")
	model.tiles[0].count = 0
	model.resolve_arrival(2, 0)
	check(model.building_at(0).level == 2 and model.collection_settings(0).radius == 2, "capture retains upgrade")
	check(model.building_refund(0) == 15 and model.demolish(2, 0) and model.tiles[0].count == 16, "upgraded demolition refunds half total investment")
	model.tiles[0].count = 40
	model.build(2, 0, "collection_tower")
	model.finished = true
	before = model.snapshot()
	check(not model.upgrade(2, 0) and model.snapshot() == before, "finished match rejects upgrade")
	print("Collection upgrade tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
