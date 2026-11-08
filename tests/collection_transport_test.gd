extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var model = Simulation.new()
	model.setup([1, 2], 123)
	model.tiles[0].owner = 1
	model.tiles[0].count = 40
	check(model.build(1, 0, "collection_tower"), "collector fixture")
	var edges: Array = []
	var far := -1
	var donor := -1
	for tile in model.tiles:
		var distance: int = model.hex_distance(model.tiles[0], tile)
		if distance == 1:
			tile.owner = 1
			tile.count = 15
			donor = tile.id
		elif distance == 2:
			edges.append(tile.id)
		elif distance > 2:
			far = tile.id
	var target: int = edges[0]
	model.tiles[target].owner = 1
	model.tiles[target].count = 50
	model.tiles[donor].count = 40
	check(model.auto_target_limit(0) == 1 and model.attack_range(0) == 2, "single target with normal dispatch range")
	for targets in [[0], [far], [target, edges[1]], [target, target], ["1"], [-1]]:
		var before: Dictionary = model.snapshot()
		check(not model.set_targets(1, 0, targets) and model.snapshot() == before, "invalid targets rejected atomically")
	check(not model.set_targets(2, 0, [target]), "foreign orders rejected")
	check(not model.set_targets(1, donor, [target]), "ordinary tiles have no automatic orders")
	check(model.set_targets(1, 0, [target]) and model.tiles[0].count == 30, "configuration does not consume energy")
	for i in range(9): model.advance()
	check(model.fleets.is_empty() and model.tiles[0].count == 30, "wait one second before first transfer")
	model.advance()
	# All six donors grow once; the chosen donor also has 25 initial surplus.
	check(model.fleets.size() == 1 and model.fleets[0].count == 62, "collect first then send all stored energy in one lance")
	check(model.tiles[0].count == 0 and model.tiles[0].owner == 1, "full transport preserves source ownership")
	for tile in model.tiles:
		if model.hex_distance(model.tiles[0], tile) == 1:
			check(tile.count == 15, "donors retain fifteen")
	for i in range(9): model.advance()
	check(model.tiles[target].count == 50, "transfer travels before reinforcement")
	model.advance()
	check(model.tiles[target].count == 112 and model.next_fleet_id == 3, "whole batch arrives and next second sends another lance")
	var clone = Simulation.new()
	clone.restore(model.snapshot())
	for i in range(35):
		model.advance()
		clone.advance()
	check(model.snapshot() == clone.snapshot(), "target, cadence and flights survive snapshots")
	check(model.set_targets(1, 0, []), "stop clears the target")
	var stopped_id: int = model.next_fleet_id
	for i in range(20): model.advance()
	check(model.next_fleet_id == stopped_id and model.tiles[0].count > 0, "stopped tower keeps collecting without firing")
	model.fleets.clear()
	for tile in model.tiles:
		if model.hex_distance(model.tiles[0], tile) == 1: tile.count = 15
	model.tiles[0].count = 0
	check(model.set_targets(1, 0, [target]), "zero energy can keep a target")
	model.tick = model.building_at(0).next_dispatch
	model.advance_buildings()
	check(model.fleets.is_empty() and model.building_at(0).targets == [target], "empty tower waits without losing orders")
	model.tiles[0].count = 14
	model.tick = model.building_at(0).next_dispatch
	model.advance_buildings()
	check(model.fleets.size() == 1 and model.fleets[0].count == 14 and model.tiles[0].count == 0, "collector has no command-tower reserve")
	for owner in [1, 2, 0]:
		model.tiles[target].owner = owner
		check(model.set_targets(1, 0, [target]), "all target factions accepted")
		model.refresh_building_orders()
		check(model.building_at(0).targets == [target], "target ownership changes preserve orders")
	model.tiles[0].count = 40
	check(model.upgrade(1, 0) and model.building_at(0).targets == [target], "upgrade preserves transfer target")
	check(model.auto_target_limit(0) == 1 and model.attack_range(0) == 2 and model.collection_settings(0).storage_cap == 500, "upgrade does not change transfer range or target count")
	var before: Dictionary = model.snapshot()
	check(not model.set_targets(1, 0, [target, edges[1]]) and model.snapshot() == before, "upgrade cannot bypass single target")
	model.resolve_impact(2, 0, 20)
	check(model.building_at(0).level == 2 and model.building_at(0).targets.is_empty(), "capture retains level and clears old owner's target")
	check(not model.set_targets(1, 0, [target]), "former owner cannot configure")
	check(model.set_targets(2, 0, [target]), "new owner can configure transport")
	check(model.demolish(2, 0) and model.tiles[0].count == 15 and model.building_at(0).is_empty(), "demolition removes orders and refunds upgraded cost")
	model.tiles[0].count = 40
	model.build(2, 0, "collection_tower")
	model.eliminated.append(2)
	check(not model.set_targets(2, 0, [target]), "eliminated player cannot configure")
	model.eliminated.clear()
	model.finished = true
	check(not model.set_targets(2, 0, [target]), "finished match cannot configure")
	print("Collection transport tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
