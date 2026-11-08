extends SceneTree
## Godot --headless --path . --script res://tests/ai_benchmark.gd -- idle|duel|openings
const Simulation = preload("res://scripts/simulation.gd")
const AI = preload("res://scripts/battle_ai.gd")
const LEVELS := ["legacy", "low", "medium", "high"]

class OriginalPlacement extends Simulation:
	func balance_openings(_homes: Array[int]) -> void:
		pass # The original generator stopped after farthest-point selection.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	match args[0] if not args.is_empty() else "idle":
		"idle": idle_matches()
		"duel": paired_matches()
		"openings":
			opening_sample(false)
			opening_sample(true)
		_:
			printerr("Expected idle, duel or openings")
			quit(1)
			return
	quit()

# Frozen copy of the former decision policy, to compare on identical current maps.
func legacy_move(sim: Simulation, rng: RandomNumberGenerator) -> String:
	if sim.tick % 20 != 0:
		return ""
	var candidates := sim.tiles.filter(func(t): return t.owner == -1 and t.count >= 8)
	if candidates.is_empty():
		return ""
	var source: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	var best := -1
	var best_score := INF
	for tile in sim.tiles:
		if tile.owner == -1 or not sim.in_range(source.id, tile.id):
			continue
		var score: float = tile.count + 2.0 * sim.hex_distance(source, tile)
		if score < best_score:
			best_score = score
			best = tile.id
	if best >= 0 and source.count > sim.tiles[best].count + sim.hex_distance(source, sim.tiles[best]):
		if sim.dispatch(-1, source.id, [best]):
			return "attack"
	return ""

func idle_matches() -> void:
	for level in range(-1, 3):
		var ticks := 0
		var commands := 0
		var wins := 0
		var tiles := 0
		var matches_with_towers := 0
		var both_types_fired := 0
		var projectiles := {"command_tower": 0, "collection_tower": 0}
		var totals := {}
		for map_seed in range(1, 17):
			var sim := Simulation.new()
			sim.setup([1, -1], map_seed)
			var rng := RandomNumberGenerator.new()
			rng.seed = map_seed
			var ai := AI.new(sim, -1, level) if level >= 0 else null
			var fired_here := {}
			while sim.tick < 1200 and not sim.finished:
				var first_new_id := sim.next_fleet_id
				sim.advance()
				# Only automatic shots can be created inside advance(), before AI input.
				for i in range(sim.fleets.size() - 1, -1, -1):
					var fleet: Dictionary = sim.fleets[i]
					if fleet.id < first_new_id:
						break
					var kind: String = sim.building_at(fleet.source).type
					projectiles[kind] += 1
					fired_here[kind] = true
				if sim.finished:
					break
				var action := ai.step() if ai != null else legacy_move(sim, rng)
				if action != "":
					commands += 1
					totals[action] = int(totals.get(action, 0)) + 1
			ticks += sim.tick
			tiles += sim.tiles.filter(func(t): return t.owner == -1).size()
			wins += int(sim.winner == -1)
			matches_with_towers += int(not sim.buildings.is_empty())
			both_types_fired += int(fired_here.size() == 2)
		print("%s ticks=%d accepted=%d APS=%.3f mean_tiles=%.2f wins=%d/16 matches_with_towers=%d both_types_fired=%d orders=%s projectiles=%s" % [
			LEVELS[level + 1], ticks, commands, commands * 10.0 / ticks, tiles / 16.0, wins,
			matches_with_towers, both_types_fired, totals, projectiles])

func paired_matches() -> void:
	for pair in [[0, 1], [1, 2], [0, 2]]:
		var wins := [0, 0]
		var unfinished := 0
		var totals := [0, 0]
		var ticks := 0
		for map_seed in range(1, 9):
			for swap in [0, 1]:
				var sim := Simulation.new()
				sim.setup([1, -1], map_seed)
				var actors := [1, -1] if swap == 0 else [-1, 1]
				var bots := [AI.new(sim, actors[0], pair[0]), AI.new(sim, actors[1], pair[1])]
				while sim.tick < 1800 and not sim.finished:
					sim.advance()
					# Keep the seat order fixed; each level plays each seat on each map.
					for i in [swap, 1 - swap]:
						if bots[i].step() != "":
							totals[i] += 1
				ticks += sim.tick
				if actors.has(sim.winner):
					wins[actors.find(sim.winner)] += 1
				else:
					unfinished += 1
		print("%s / %s wins=%s unfinished=%d ticks=%d APS=%.3f/%.3f" % [
			LEVELS[pair[0] + 1], LEVELS[pair[1] + 1], wins, unfinished, ticks,
			totals[0] * 10.0 / ticks, totals[1] * 10.0 / ticks])

func opening_sample(balanced: bool) -> void:
	for seats in [2, 3, 4]:
		var total_gap := 0
		var worst := 0
		var closest := 91
		for map_seed in range(1, 65):
			var sim: Simulation = Simulation.new() if balanced else OriginalPlacement.new()
			sim.setup([1, -1, 3, 4].slice(0, seats), map_seed)
			var moves: Array[int] = []
			for home in sim.tiles:
				if home.owner == 0:
					continue
				var options := 0
				for tile in sim.tiles:
					var distance := sim.hex_distance(home, tile)
					if tile.owner == 0 and distance <= Simulation.DEFAULT_ATTACK_RANGE:
						options += 1
					elif tile.owner != 0 and distance > 0:
						closest = mini(closest, distance)
				moves.append(options)
			var gap: int = moves.max() - moves.min()
			worst = maxi(worst, gap)
			total_gap += gap
		print("balanced=%s seats=%d mean_gap=%.3f max_gap=%d closest=%d" % [balanced, seats, total_gap / 64.0, worst, closest])
