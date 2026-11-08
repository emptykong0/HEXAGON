extends SceneTree
const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/battle_ai.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func fixture(cells: Array) -> Simulation:
	var sim := Simulation.new()
	sim.match_players = [1, -1]
	for cell in cells:
		sim.tiles.append({"id": sim.tiles.size(), "q": cell[0], "r": cell[1], "owner": cell[2],
			"count": cell[3], "building_id": -1, "attack_range": Simulation.DEFAULT_ATTACK_RANGE})
	return sim

func next_action(sim: Simulation, bot: AI) -> String:
	while sim.tick < bot.next_turn and not sim.finished:
		sim.advance()
	return bot.step()

func _initialize() -> void:
	for level in [AI.Difficulty.LOW, AI.Difficulty.MEDIUM, AI.Difficulty.HIGH]:
		test_cadence(level)
		test_command_tower(level)
		test_collector(level)
	test_upgrade()
	test_bank_salvo()
	test_projection()
	test_defense()
	test_joint_attack()
	print("Battle AI tests: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func test_cadence(level: AI.Difficulty) -> void:
	# Ample independent legal moves isolate the operation budget from energy scarcity.
	var sim := fixture([[0, 0, -1, 20], [20, 0, 1, 50]])
	for i in range(1, 15):
		sim.tiles.append({"id": i + 1, "q": i, "r": 0, "owner": 0, "count": 5, "building_id": -1, "attack_range": 2})
	sim.tiles[0].attack_range = 14
	var bot := AI.new(sim, -1, level)
	var accepted := 0
	for i in range(40):
		sim.advance()
		sim.tiles[0].count = 30
		var action := bot.step()
		if action != "":
			accepted += 1
			check(sim.tick % AI.INTERVAL_TICKS[level] == 0, "accepted at a scheduled tick")
		check(bot.step() == "", "no second order on one simulation tick")
	check(accepted == [2, 4, 8][level], "low/medium/high accept 0.5/1/2 orders per second when supplied")
	sim.eliminated.append(-1)
	sim.tick += 20
	check(bot.step() == "", "eliminated AI cannot act")
	sim.eliminated.clear()
	sim.finished = true
	check(bot.step() == "", "result freezes AI")

func test_command_tower(level: AI.Difficulty) -> void:
	var sim := fixture([[0, 0, -1, 39], [-1, 0, -1, 0], [0, -1, -1, 0], [3, 0, 0, 5], [7, 0, 1, 50]])
	var bot := AI.new(sim, -1, level)
	check(next_action(sim, bot) == "command_tower", "all levels build for a third-ring objective")
	check(sim.building_at(0).get("type") == "command_tower" and sim.tiles[0].count == 39 + sim.tick / 10 - 10, "ordinary construction fee charged locally")
	check(next_action(sim, bot) == "targets" and sim.building_at(0).targets == [3], "command tower gets a legal target on another turn")
	for i in range(10):
		sim.advance()
	check(sim.fleets.size() == 1 and sim.fleets[0].target == 3 and sim.tiles[0].count == 15, "automatic salvo leaves the same reserve as a player tower")
	for i in range(15):
		sim.advance()
	check(sim.tiles[3].owner == -1, "AI command tower actually captures at distance three")

func test_collector(level: AI.Difficulty) -> void:
	var sim := fixture([[0, 0, -1, 18], [-1, 0, -1, 38], [1, 0, -1, 38], [2, 0, 0, 15], [6, 0, 1, 50]])
	var bot := AI.new(sim, -1, level)
	check(next_action(sim, bot) == "collection_tower" and sim.building_at(0).get("type") == "collection_tower", "all levels choose the two-donor collector site")
	check(next_action(sim, bot) == "targets" and sim.building_at(0).targets == [3], "collector configures one reachable outlet")
	for i in range(10):
		sim.advance()
	check(sim.fleets.size() == 1 and sim.fleets[0].remaining >= 50 and sim.tiles[0].count == 0, "AI collector converts real donor surplus into a whole delivery")
	check(sim.tiles[1].count >= 15 and sim.tiles[2].count >= 15, "donors retain reserve")
	for i in range(10):
		sim.advance()
	check(sim.tiles[3].owner == -1, "AI collector delivery lands")

func test_upgrade() -> void:
	for level in [AI.Difficulty.MEDIUM, AI.Difficulty.HIGH]:
		var sim := fixture([[0, 0, -1, 10], [-1, 0, -1, 15], [1, 0, -1, 15], [0, 1, -1, 15],
			[0, -1, -1, 15], [-2, 0, -1, 34], [0, 2, -1, 34], [2, 0, 1, 200]])
		sim.build(-1, 0, "collection_tower")
		sim.set_targets(-1, 0, [7])
		var bot := AI.new(sim, -1, level)
		check(next_action(sim, bot) == "save_upgrade" and sim.building_at(0).targets.is_empty(), "working collector pauses deliveries to fund useful second ring")
		var upgraded := false
		var restarted := false
		for i in range(120):
			sim.advance()
			var balance: int = sim.tiles[0].count
			var action := bot.step()
			if action == "upgrade":
				upgraded = sim.building_at(0).level == 2 and sim.tiles[0].count == balance - 20
			if upgraded and not sim.building_at(0).targets.is_empty():
				restarted = true
				break
		check(upgraded and restarted, "collector pays twenty, upgrades and resumes a legal delivery")

func test_projection() -> void:
	var sim := fixture([[0, 0, -1, 13], [0, 1, 1, 20], [1, 0, 0, 13], [1, 1, -1, 10], [4, 0, 1, 80]])
	sim.tick = 7
	sim.dispatch(-1, 0, [2])
	sim.dispatch(1, 1, [2])
	sim.dispatch(-1, 3, [2])
	var bot := AI.new(sim, -1, AI.Difficulty.HIGH)
	bot.read_board()
	var expected := bot.forecast(2, 20)
	var frozen := sim.snapshot()
	check(bot.forecast(4, 20).count == 80 and frozen == sim.snapshot(), "forecast preserves over-cap energy and does not modify the model")
	while sim.tick < 20:
		sim.advance()
	check(sim.tiles[2].owner == expected.owner and sim.tiles[2].count == expected.count, "growth phase and simultaneous fleet ID order match live impacts")

func test_bank_salvo() -> void:
	var sim := fixture([[0, 0, -1, 25], [3, 0, 0, 15], [8, 0, 1, 50]])
	sim.build(-1, 0, "command_tower")
	var bot := AI.new(sim, -1, AI.Difficulty.MEDIUM)
	while sim.tick < 170:
		sim.advance()
		bot.step()
		if sim.tick < 140:
			check(sim.fleets.is_empty(), "tower banks energy against a saturated neutral")
	check(sim.tiles[1].owner == -1, "one saved salvo breaks the one-per-second stalemate")

func test_defense() -> void:
	var sim := fixture([[0, 0, -1, 4], [-1, 0, -1, 15], [2, 0, 1, 12]])
	sim.dispatch(1, 2, [0])
	var bot := AI.new(sim, -1, AI.Difficulty.HIGH)
	check(next_action(sim, bot) == "reinforce" and sim.fleets[-1].target == 0, "high saves a projected loss before the deadline")
	while sim.tick < 10:
		sim.advance()
	check(sim.tiles[0].owner == -1 and sim.tiles[0].count == 8, "timely defense survives both hits")

func test_joint_attack() -> void:
	var cells := [[-1, 0, -1, 11], [0, -1, -1, 12], [0, 0, 1, 19]]
	var sim := fixture(cells)
	var bot := AI.new(sim, -1, AI.Difficulty.HIGH)
	check(next_action(sim, bot) == "attack" and not bot.followup.is_empty(), "two individually insufficient sources plan an affordable capture")
	check(next_action(sim, bot) == "attack" and bot.followup.is_empty(), "second salvo consumes a separate operation")
	while sim.tick < 15:
		sim.advance()
	check(sim.finished and sim.winner == -1, "combined attack resolves through normal victory rules")
	sim = fixture(cells)
	bot = AI.new(sim, -1, AI.Difficulty.HIGH)
	next_action(sim, bot)
	var partner: int = bot.followup.source
	sim.resolve_impact(1, partner, 40)
	next_action(sim, bot)
	check(bot.followup.is_empty() and sim.next_fleet_id == 2, "loss of a planned partner cancels the second salvo")
