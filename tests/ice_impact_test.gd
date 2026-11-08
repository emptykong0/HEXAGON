extends SceneTree
const Model = preload("res://scripts/simulation.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var sim = Model.new()
	sim.setup([1,2], 123)
	var target := 1
	for scenario in [[2,7,4,2,3], [2,7,7,1,0], [2,7,12,1,5], [0,0,12,1,12], [1,50,20,1,70]]:
		sim.tiles[target].owner = scenario[0]
		sim.tiles[target].count = scenario[1]
		sim.resolve_impact(1, target, scenario[2])
		check(sim.tiles[target].owner == scenario[3] and sim.tiles[target].count == scenario[4], "atomic capture/reinforcement arithmetic")
	sim.setup([1,2], 123)
	var source := 0
	target = 1
	sim.tiles[source].owner = 1
	sim.tiles[source].count = 30
	sim.tiles[target].owner = 2
	sim.tiles[target].count = 10
	check(sim.dispatch(1,source,[target]), "dispatch")
	check(sim.fleets.size() == 1 and sim.tiles[source].count == 0, "one lance holds all energy")
	var duration: int = sim.fleets[0].duration
	for i in range(duration - 1): sim.advance()
	check(sim.tiles[target].count == 10 and sim.fleets[0].remaining == 30, "no partial damage before hit")
	var clone = Model.new()
	clone.restore(sim.snapshot())
	sim.advance()
	clone.advance()
	check(sim.fleets.is_empty() and sim.tiles[target].owner == 1 and sim.tiles[target].count == 20, "single full impact")
	check(sim.snapshot() == clone.snapshot() and sim.impacts.size() == 1, "snapshot reproduces damage and impact event")
	print("Ice impact tests: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
