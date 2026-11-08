extends RefCounted
## One instance per computer player per match. Every order uses the host model.
const Simulation = preload("res://scripts/simulation.gd")
const Content = preload("res://scripts/content.gd")
enum Difficulty { LOW, MEDIUM, HIGH }
const LABELS := ["低", "中", "高"]
const INTERVAL_TICKS := [20, 10, 5]
const HORIZON_SECONDS := [10, 12, 16]
const RELAY_MINIMUM := [15, 10, 6]

var model: Simulation
var actor: int
var difficulty: Difficulty
var next_turn: int
var distances: Array[PackedInt32Array] = []
var followup: Dictionary = {}
var saving_source := -1
var saving_deadline := 0

# Rebuilt from visible board state at each decision.
var owned: Array[int] = []
var territories: Dictionary = {}
var structures: Dictionary = {}
var collectors: Array[int] = []
var commanders: Array[int] = []
var covered: Dictionary = {}
var incoming: Dictionary = {}
var forecasts: Dictionary = {}
var loss_tick: Dictionary = {}
var frontier := PackedInt32Array()
var enemy_distance := PackedInt32Array()
var ranges := PackedInt32Array()
var available := PackedInt64Array()
var can_leave: Dictionary = {}
var best: Dictionary = {}
var best_score: float

func _init(simulation: Simulation, player: int, level: Difficulty) -> void:
	model = simulation
	actor = player
	difficulty = level
	next_turn = model.tick + INTERVAL_TICKS[difficulty]
	for tile in model.tiles:
		var row := PackedInt32Array()
		for other in model.tiles:
			row.append(model.hex_distance(tile, other))
		distances.append(row)
	frontier.resize(distances.size())
	enemy_distance.resize(distances.size())
	ranges.resize(distances.size())
	available.resize(distances.size())

## Returns the accepted player command, or an empty string for a wait.
## Automatic tower fire does not spend an action slot.
func step() -> String:
	if model.tick < next_turn or model.finished or model.eliminated.has(actor):
		return ""
	next_turn = model.tick + INTERVAL_TICKS[difficulty]
	read_board()
	best = {}
	best_score = -INF
	if not followup.is_empty():
		var source: int = followup.source
		var target: int = followup.target
		if owned.has(source) and distances[source][target] <= ranges[source] and can_leave[source]:
			var state := forecast(target, model.tick + Simulation.flight_ticks(distances[source][target]))
			if state.owner != actor and available[source] > 0 and available[source] >= state.count:
				consider(70.0, "attack", source, [target])
		followup = {}
	for source in owned:
		var building: Dictionary = structures.get(source, {})
		if building.is_empty():
			consider_construction(source)
		else:
			var saving := false
			if building.type == "collection_tower" and building.get("level", 1) == 1 and difficulty != Difficulty.LOW:
				saving = consider_collection(source, true)
			if not saving and model.auto_target_limit(source) != 0:
				consider_tower_order(source, building)
		if available[source] > 0 and can_leave[source]:
			consider_moves(source, building)
	if best.is_empty():
		return ""
	var accepted := false
	match best.action:
		"attack", "reinforce":
			accepted = model.dispatch(actor, best.source, best.targets)
		"command_tower", "collection_tower":
			accepted = model.build(actor, best.source, best.action)
		"targets", "save_upgrade":
			accepted = model.set_targets(actor, best.source, best.targets)
		"upgrade":
			accepted = model.upgrade(actor, best.source)
	if not accepted:
		return ""
	followup = best.get("followup", {})
	if best.action == "save_upgrade":
		saving_source = best.source
		saving_deadline = model.tick + 5 * Simulation.TICKS_PER_SECOND
	elif best.action == "upgrade" and best.source == saving_source:
		saving_source = -1
	return best.action

func consider(score: float, action: String, source: int, targets: Array = [], second: Dictionary = {}) -> void:
	if score > best_score:
		best_score = score
		best = {"action": action, "source": source, "targets": targets, "followup": second}

func read_board() -> void:
	owned.clear()
	territories.clear()
	structures.clear()
	collectors.clear()
	commanders.clear()
	covered.clear()
	incoming.clear()
	forecasts.clear()
	loss_tick.clear()
	can_leave.clear()
	var outside: Array[int] = []
	var enemies: Array[int] = []
	for tile in model.tiles:
		territories[tile.owner] = int(territories.get(tile.owner, 0)) + 1
		if tile.owner == actor:
			owned.append(tile.id)
		else:
			outside.append(tile.id)
			if tile.owner != 0:
				enemies.append(tile.id)
	if difficulty != Difficulty.LOW:
		for tile in model.tiles:
			var nearest := model.tiles.size()
			for enemy in enemies:
				nearest = mini(nearest, distances[tile.id][enemy])
			enemy_distance[tile.id] = nearest
	for building in model.buildings:
		structures[building.tile] = building
		if building.owner == actor:
			if building.type == "collection_tower":
				collectors.append(building.tile)
			elif building.type == "command_tower":
				commanders.append(building.tile)
	for fleet in model.fleets:
		if not incoming.has(fleet.target):
			incoming[fleet.target] = []
		incoming[fleet.target].append(fleet)
	for group in incoming.values():
		if group.size() > 1:
			group.sort_custom(arrives_first)
	for source in owned:
		var depth := model.tiles.size()
		for other in outside:
			depth = mini(depth, distances[source][other])
		frontier[source] = depth
		ranges[source] = model.attack_range(source)
		available[source] = model.dispatchable_count(source)
		can_leave[source] = difficulty != Difficulty.HIGH or safe_after_spending(source, available[source])
		if difficulty == Difficulty.HIGH and incoming.has(source):
			for fleet in incoming.get(source, []):
				if fleet.owner != actor and forecast(source, fleet.next_arrival).owner != actor:
					loss_tick[source] = fleet.next_arrival
					break
	for source in collectors:
		var radius: int = model.collection_settings(source).radius
		for donor in owned:
			if not structures.has(donor) and distances[source][donor] <= radius:
				covered[donor] = true
	if not collectors.has(saving_source):
		saving_source = -1

static func arrives_first(a: Dictionary, b: Dictionary) -> bool:
	if a.next_arrival == b.next_arrival:
		return a.id < b.id
	return a.next_arrival < b.next_arrival

# Growth and impacts share the actual combat arithmetic. Only orders already
# visible in flight are facts; future player and tower orders can change the result.
func project(target: int, until: int, initial_count: int, extra: Dictionary = {}) -> Dictionary:
	var state := {"owner": model.tiles[target].owner, "count": initial_count}
	var previous := model.tick
	var flights: Array = incoming.get(target, [])
	if not extra.is_empty():
		flights = flights.duplicate()
		flights.append(extra)
		flights.sort_custom(arrives_first)
	for fleet in flights:
		if fleet.next_arrival > until:
			break
		state.count = Simulation.grown_count(state.owner, state.count, previous, fleet.next_arrival)
		Simulation.apply_impact_to(state, fleet.owner, fleet.remaining)
		previous = fleet.next_arrival
	state.count = Simulation.grown_count(state.owner, state.count, previous, until)
	return state

func forecast(target: int, until: int) -> Dictionary:
	var key := Vector2i(target, until)
	if not forecasts.has(key):
		forecasts[key] = project(target, until, model.tiles[target].count)
	return forecasts[key]

func safe_after_spending(source: int, cost: int) -> bool:
	var left: int = model.tiles[source].count - cost
	for fleet in incoming.get(source, []):
		if fleet.owner != actor and project(source, fleet.next_arrival, left).owner != actor:
			return false
	return true

func proposed_flight(amount: int, arrival: int) -> Dictionary:
	return {"owner": actor, "remaining": amount, "next_arrival": arrival, "id": model.next_fleet_id}

func consider_moves(source: int, building: Dictionary) -> void:
	var amount := available[source]
	for tile in model.tiles:
		var target: int = tile.id
		var distance := distances[source][target]
		if distance == 0 or distance > ranges[source]:
			continue
		var arrival := model.tick + Simulation.flight_ticks(distance)
		if loss_tick.has(target) and arrival <= loss_tick[target]:
			var aided := project(target, loss_tick[target], tile.count, proposed_flight(amount, arrival))
			if aided.owner == actor:
				consider(90.0 - distance + mini(aided.count, 10) * 0.1, "reinforce", source, [target])
		if not building.is_empty():
			continue # A configured tower runs on its own clock.
		var state := forecast(target, arrival)
		if state.owner == actor:
			if tile.owner == actor and frontier[target] < frontier[source] and amount >= RELAY_MINIMUM[difficulty] and not covered.has(source):
				var relay_score := 5.0 + mini(12, amount / 3) - frontier[target] - 0.3 * distance
				consider(relay_score, "reinforce", source, [target])
			continue
		if amount >= state.count:
			var score: float = capture_value(state, source, target) - 0.55 * state.count - distance + 0.16 * mini(18, amount - state.count)
			consider(score, "attack", source, [target])
		elif difficulty == Difficulty.HIGH and state.owner != 0 and amount >= 5 and amount * 3 >= state.count:
			consider_joint_attack(source, target, arrival, state)

func capture_value(state: Dictionary, source: int, target: int) -> float:
	var value := 24.0
	if difficulty != Difficulty.LOW:
		value += 2.0 * (enemy_distance[source] - enemy_distance[target])
	if state.owner != 0:
		value += 10.0
		if territories.get(state.owner, 0) == 1:
			value += 45.0
	if structures.has(target):
		value += 6.0
	return value

func consider_joint_attack(source: int, target: int, first_eta: int, state: Dictionary) -> void:
	var first := proposed_flight(available[source], first_eta)
	for partner in owned:
		if partner == source or structures.has(partner) or not can_leave[partner] or available[partner] <= 0:
			continue
		var distance := distances[partner][target]
		if distance > ranges[partner] or available[source] + available[partner] < state.count:
			continue
		var second_eta: int = model.tick + INTERVAL_TICKS[difficulty] + Simulation.flight_ticks(distance)
		if second_eta < first_eta:
			continue # Evaluate the opposite firing order when visiting the other source.
		var before_second := project(target, second_eta, model.tiles[target].count, first)
		if before_second.owner != actor and available[partner] >= before_second.count:
			var score: float = capture_value(state, source, target) - 0.55 * state.count - 4.0 - distance
			consider(score, "attack", source, [target], {"source": partner, "target": target})

func consider_construction(source: int) -> void:
	var tile: Dictionary = model.tiles[source]
	if owned.size() < 3:
		return
	if owned.size() >= 3 + 6 * collectors.size():
		consider_collection(source, false)
	var tower: Dictionary = Content.BUILDINGS.command_tower
	if tile.count < tower.cost or owned.size() < 3 + 7 * commanders.size() or covered.has(source):
		return
	for other in commanders:
		if distances[source][other] <= Simulation.DEFAULT_ATTACK_RANGE:
			return
	var horizon: int = HORIZON_SECONDS[difficulty]
	var until := model.tick + horizon * Simulation.TICKS_PER_SECOND
	var mobilizable := maxi(0, Simulation.grown_count(actor, tile.count - tower.cost, model.tick, until) - int(tower.dispatch_reserve))
	if mobilizable < 3 or not safe_after_spending(source, tower.cost):
		return
	var extra_targets := 0
	for target in model.tiles:
		var distance := distances[source][target.id]
		if target.owner != actor and distance > ranges[source] and distance <= int(tower.attack_range):
			extra_targets += 1
	if extra_targets > 0:
		var score := 13.0 + mini(7, extra_targets) * 1.4 + mini(12, mobilizable) * 0.45
		consider(score, "command_tower", source)

# Estimate the next five seconds of deposits before pausing a working collector.
# Returning true keeps the collector saving while other tiles can still act.
func consider_collection(source: int, upgrading: bool) -> bool:
	var tower: Dictionary = Content.BUILDINGS.collection_tower
	var settings: Dictionary = tower.upgrade if upgrading else tower
	var cost: int = settings.cost
	var count: int = model.tiles[source].count
	if (count < cost and not upgrading) or not safe_after_spending(source, mini(count, cost)):
		if saving_source == source:
			saving_source = -1
		return false
	var supply := 0
	var donors := 0
	var sites := 0
	var until: int = model.tick + HORIZON_SECONDS[difficulty] * Simulation.TICKS_PER_SECOND
	var save_until := model.tick + 5 * Simulation.TICKS_PER_SECOND
	var savings := Simulation.grown_count(actor, count, model.tick, save_until)
	for donor in owned:
		var distance := distances[source][donor]
		if donor == source or distance > int(settings.radius) or structures.has(donor):
			continue
		if upgrading and distance <= int(tower.radius):
			savings += maxi(0, Simulation.grown_count(actor, model.tiles[donor].count, model.tick, save_until) - int(tower.reserve))
		if covered.has(donor):
			continue
		sites += 1
		var excess := maxi(0, Simulation.grown_count(actor, model.tiles[donor].count, model.tick, until) - int(tower.reserve))
		if excess > 0:
			donors += 1
			supply += excess
	# Once the order has been stopped, a temporary dip in a donor's energy
	# does not cancel the investment. Lost supply territory or a missed deadline does.
	if upgrading and saving_source == source:
		if sites >= 2:
			if count >= cost:
				consider(48.0, "upgrade", source)
				return true
			if model.tick < saving_deadline:
				return true
		saving_source = -1
		return false
	var usable := mini(supply, maxi(0, int(settings.storage_cap) - maxi(0, count - cost)))
	if donors < 2 or usable <= cost:
		return false
	var score := 17.0 + minf(13.0, (usable - cost) * 0.4) + mini(4, donors)
	if upgrading and count < cost:
		if savings < cost or saving_source >= 0:
			return false
		if not structures[source].targets.is_empty():
			consider(score - 3.0, "save_upgrade", source)
		return true
	consider(score, "upgrade" if upgrading else "collection_tower", source)
	return upgrading

func consider_tower_order(source: int, building: Dictionary) -> void:
	var current: Array = building.targets
	var first := -1
	var second := -1
	var top := -INF
	var runner_up := -INF
	var retained := 0
	var current_value := INF
	var dispatch_tick := model.tick + Simulation.TICKS_PER_SECOND
	var origin := forecast(source, dispatch_tick)
	var batch: int = maxi(0, origin.count - int(Content.BUILDINGS[building.type].dispatch_reserve)) if origin.owner == actor else 0
	for tile in model.tiles:
		var target: int = tile.id
		var distance := distances[source][target]
		if distance == 0 or distance > ranges[source]:
			continue
		var state := forecast(target, dispatch_tick + Simulation.flight_ticks(distance))
		var value: float
		if state.owner == actor:
			if current.has(target) and tile.owner != actor:
				return # The current attack is already capturing this cell. Let it land.
			if tile.owner != actor or frontier[target] >= frontier[source]:
				continue
			value = 7.0 - frontier[target]
		else:
			# A lone +1/s tower can spend forever matching a neutral's growth.
			# Let it bank a capturing salvo or supply a closer friendly cell.
			if building.type == "command_tower" and state.owner == 0 and batch < state.count:
				continue
			value = capture_value(state, source, target) - 0.5 * mini(60, state.count)
		value -= 0.6 * distance
		if current.has(target):
			value += 2.0
			retained += 1
			current_value = minf(current_value, value)
		if value > top:
			runner_up = top
			second = first
			top = value
			first = target
		elif value > runner_up:
			runner_up = value
			second = target
	var orders: Array = []
	if first >= 0:
		orders.append(first)
	if building.type == "command_tower" and difficulty != Difficulty.LOW and second >= 0:
		var a := forecast(first, dispatch_tick + Simulation.flight_ticks(distances[source][first]))
		var b := forecast(second, dispatch_tick + Simulation.flight_ticks(distances[source][second]))
		if a.owner != actor and b.owner != actor and batch / 2 >= maxi(1, maxi(a.count, b.count)):
			orders.append(second)
	orders.sort()
	if current != orders:
		if current.size() == orders.size() and retained == current.size() and top < current_value + 5.0:
			return
		consider(40.0 if current.is_empty() else 21.0, "targets", source, orders)
