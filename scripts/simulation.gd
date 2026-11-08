extends RefCounted
## Only the host advances this model. No UI or transport dependencies.
signal domain_event(event: Dictionary)
const Content = preload("res://scripts/content.gd")
const TICKS_PER_SECOND = 10
const NEUTRAL_GROWTH_CAP = 15
const OWNED_GROWTH_CAP = 50
const DEFAULT_ATTACK_RANGE = 2
const MAP_TILE_COUNT = 91
const MAP_Q_RADIUS = 6
const MAP_R_RADIUS = 5
const HEX_NEIGHBORS = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
var tick: int = 0
var tiles: Array = []
var fleets: Array = []
var buildings: Array = []
var systems: Array = []
var impacts: Array = []
var next_fleet_id: int = 1
var match_players: Array = []
var eliminated: Array = []
var finished := false
var winner: int = 0

func setup(players: Array, map_seed: int = -1) -> void:
	tick = 0
	tiles.clear()
	fleets.clear()
	impacts.clear()
	buildings.clear()
	next_fleet_id = 1
	match_players = players.duplicate()
	eliminated.clear()
	finished = false
	winner = 0
	var map_rng := RandomNumberGenerator.new()
	if map_seed < 0:
		map_rng.randomize()
	else:
		map_rng.seed = map_seed
	var occupied: Dictionary = {}
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	while tiles.size() < MAP_TILE_COUNT:
		var best_index := 0
		var best_score := INF
		for i in range(frontier.size()):
			var cell: Vector2i = frontier[i]
			var adjacent := 0
			for direction in HEX_NEIGHBORS:
				if occupied.has(cell + direction):
					adjacent += 1
			var distance := maxi(absi(cell.x), maxi(absi(cell.y), absi(cell.x + cell.y)))
			var score: float = distance * 0.4 - adjacent * 0.5 + map_rng.randf_range(0, 7)
			if score < best_score:
				best_score = score
				best_index = i
		var chosen: Vector2i = frontier.pop_at(best_index)
		occupied[chosen] = true
		tiles.append({"id": tiles.size(), "q": chosen.x, "r": chosen.y, "owner": 0, "count": 5, "building_id": -1, "attack_range": DEFAULT_ATTACK_RANGE})
		for direction in HEX_NEIGHBORS:
			var neighbor: Vector2i = chosen + direction
			if absi(neighbor.x) <= MAP_Q_RADIUS and absi(neighbor.y) <= MAP_R_RADIUS and absi(neighbor.x + neighbor.y) <= MAP_Q_RADIUS:
				if not occupied.has(neighbor) and not frontier.has(neighbor):
					frontier.append(neighbor)
	var homes := choose_homes(players.size(), map_rng)
	for i in range(players.size()):
		tiles[homes[i]].owner = players[i]
		tiles[homes[i]].count = 20

func choose_homes(seats: int, map_rng: RandomNumberGenerator) -> Array[int]:
	# Start from distant positions, then balance the number of legal opening moves.
	var homes: Array[int] = []
	for seat in range(seats):
		var best_id := -1
		var best_distance := -1.0
		for tile in tiles:
			if homes.has(tile.id):
				continue
			var separation: int = hex_distance(tile, {"q": 0, "r": 0})
			if not homes.is_empty():
				separation = 100
				for home in homes:
					separation = mini(separation, hex_distance(tile, tiles[home]))
			var score: float = separation + map_rng.randf() * 0.5
			if score > best_distance:
				best_distance = score
				best_id = tile.id
		homes.append(best_id)
	balance_openings(homes)
	return homes

func balance_openings(homes: Array[int]) -> void:
	var seats := homes.size()
	if seats < 2:
		return
	var opening_moves := PackedInt32Array()
	opening_moves.resize(tiles.size())
	for tile in tiles:
		for other in tiles:
			if tile.id != other.id and hex_distance(tile, other) <= DEFAULT_ATTACK_RANGE:
				opening_moves[tile.id] += 1
	var spacing := tiles.size()
	for i in range(seats):
		for j in range(i):
			spacing = mini(spacing, hex_distance(tiles[homes[i]], tiles[homes[j]]))
	# Give up at most one hex of separation; keep disjoint opening ranges where possible.
	var minimum_spacing := mini(spacing, maxi(2 * DEFAULT_ATTACK_RANGE + 1, spacing - 1))
	for pass_index in range(2):
		for seat in range(seats):
			var others := homes.duplicate()
			others.remove_at(seat)
			var low := tiles.size()
			var high := 0
			for home in others:
				low = mini(low, opening_moves[home])
				high = maxi(high, opening_moves[home])
			var best := homes[seat]
			var best_score := opening_score(opening_moves[best], low, high)
			for tile in tiles:
				var score := opening_score(opening_moves[tile.id], low, high)
				if score >= best_score:
					continue
				var clear := true
				for home in others:
					if hex_distance(tile, tiles[home]) < minimum_spacing:
						clear = false
						break
				if clear:
					best = tile.id
					best_score = score
			homes[seat] = best

func opening_score(moves: int, other_min: int, other_max: int) -> int:
	var fewest := mini(moves, other_min)
	# Minimize the spread first. Among ties improve the weakest opening.
	return (maxi(moves, other_max) - fewest) * (tiles.size() + 1) - fewest

func hex_distance(a: Dictionary, b: Dictionary) -> int:
	var dq: int = a.q - b.q
	var dr: int = a.r - b.r
	return maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))

static func flight_ticks(distance: int, unit_type: String = "drone") -> int:
	return maxi(1, distance * int(Content.UNITS[unit_type].travel_ticks_per_hex))

## Natural growth between two post-tick states, with no intervening transfers.
static func grown_count(owner: int, count: int, from_tick: int, to_tick: int) -> int:
	var pulses := to_tick / TICKS_PER_SECOND - from_tick / TICKS_PER_SECOND
	var cap := NEUTRAL_GROWTH_CAP if owner == 0 else OWNED_GROWTH_CAP
	return count + mini(maxi(0, cap - count), pulses)

## Also used on temporary garrisons when the AI forecasts known arrivals.
static func apply_impact_to(tile: Dictionary, actor: int, amount: int) -> void:
	var owner: int = tile.owner
	var count: int = tile.count
	if owner == actor:
		tile.count = count + amount
	elif amount >= count:
		tile.owner = actor
		tile.count = amount - count
	else:
		tile.count = count - amount

## Attack range is independent of a building's collection/interception radius.
func attack_range(source: int) -> int:
	var tile: Dictionary = tiles[source]
	var value: int = int(tile.get("attack_range", DEFAULT_ATTACK_RANGE))
	var building := building_at(source)
	if not building.is_empty():
		var definition: Dictionary = Content.BUILDINGS.get(building.get("type", ""), {})
		value = int(building.get("attack_range", definition.get("attack_range", value)))
	return maxi(0, value)

func in_range(source: int, target: int) -> bool:
	return source >= 0 and source < tiles.size() and target >= 0 and target < tiles.size() and hex_distance(tiles[source], tiles[target]) <= attack_range(source)

func building_at(source: int) -> Dictionary:
	if source < 0 or source >= tiles.size() or tiles[source].building_id == -1:
		return {}
	for building in buildings:
		if building.id == tiles[source].building_id:
			return building
	return {}

func can_command(actor: int, source: int) -> bool:
	return not finished and actor != 0 and match_players.has(actor) and not eliminated.has(actor) and source >= 0 and source < tiles.size() and tiles[source].owner == actor

func build(actor: int, source: int, kind: String) -> bool:
	if not can_command(actor, source) or not ["command_tower", "collection_tower"].has(kind):
		return false
	var cost: int = Content.BUILDINGS[kind].cost
	if tiles[source].building_id != -1 or tiles[source].count < cost:
		return false
	# IDs derive from simulation time and tile, and are included in snapshots.
	var id: int = tick * MAP_TILE_COUNT + source
	tiles[source].count -= cost
	tiles[source].building_id = id
	buildings.append({"id": id, "tile": source, "type": kind, "level": 1, "owner": actor, "targets": [], "cursor": 0, "next_dispatch": tick + TICKS_PER_SECOND, "next_collection": tick + TICKS_PER_SECOND})
	return true

func collection_settings(source: int) -> Dictionary:
	var definition: Dictionary = Content.BUILDINGS.collection_tower
	return definition.upgrade if int(building_at(source).get("level", 1)) >= 2 else definition

func upgrade(actor: int, source: int) -> bool:
	if not can_command(actor, source):
		return false
	var building := building_at(source)
	if building.get("type", "") != "collection_tower" or int(building.get("level", 1)) >= 2:
		return false
	var cost: int = Content.BUILDINGS.collection_tower.upgrade.cost
	if tiles[source].count < cost:
		return false
	tiles[source].count -= cost
	building.level = 2
	return true

func building_refund(source: int) -> int:
	var building := building_at(source)
	if building.is_empty():
		return 0
	var definition: Dictionary = Content.BUILDINGS[building.type]
	var invested: int = definition.get("cost", 0)
	if int(building.get("level", 1)) >= 2:
		invested += int(definition.get("upgrade", {}).get("cost", 0))
	return invested / 2

func demolish(actor: int, source: int) -> bool:
	if not can_command(actor, source):
		return false
	var building := building_at(source)
	if building.is_empty():
		return false
	tiles[source].count += building_refund(source)
	buildings.erase(building)
	tiles[source].building_id = -1
	return true

## 0: no automatic orders; -1: unlimited; positive: maximum target count.
func auto_target_limit(source: int) -> int:
	var definition: Dictionary = Content.BUILDINGS.get(building_at(source).get("type", ""), {})
	return int(definition.get("target_limit", 0))

func set_targets(actor: int, source: int, targets: Array) -> bool:
	if not can_command(actor, source):
		return false
	var building := building_at(source)
	var limit := auto_target_limit(source)
	if limit == 0 or (limit > 0 and targets.size() > limit):
		return false
	var unique: Array = []
	for target in targets:
		if typeof(target) != TYPE_INT or target == source or not in_range(source, target) or unique.has(target):
			return false
		unique.append(target)
	building.targets = unique
	building.cursor = 0
	building.next_dispatch = tick + TICKS_PER_SECOND
	return true

func refresh_building_orders() -> void:
	for building in buildings:
		var source: int = building.tile
		update_building_owner(building, tiles[source].owner)
		building.targets = building.targets.filter(func(target): return in_range(source, target))

func update_building_owner(building: Dictionary, owner: int) -> void:
	if building.owner != owner:
		building.owner = owner
		building.targets = []
		building.cursor = 0

func dispatchable_count(source: int) -> int:
	var definition: Dictionary = Content.BUILDINGS.get(building_at(source).get("type", ""), {})
	var reserve: int = int(definition.get("dispatch_reserve", 0))
	return maxi(0, int(tiles[source].count) - reserve)

func advance_collection() -> void:
	# Host-only, stable building order; transferred energy is removed immediately.
	for building in buildings:
		if building.type != "collection_tower" or tick < building.next_collection:
			continue
		building.next_collection = tick + TICKS_PER_SECOND
		var source: int = building.tile
		var owner: int = tiles[source].owner
		if not can_command(owner, source):
			continue
		var definition := collection_settings(source)
		for tile in tiles:
			var distance := hex_distance(tiles[source], tile)
			if tile.owner != owner or distance < 1 or distance > int(definition.radius):
				continue
			if ["command_tower", "collection_tower"].has(building_at(tile.id).get("type", "")):
				continue
			var amount: int = mini(maxi(0, int(tile.count) - int(Content.BUILDINGS.collection_tower.reserve)), maxi(0, int(definition.storage_cap) - int(tiles[source].count)))
			tile.count -= amount
			tiles[source].count += amount

func advance_buildings() -> void:
	refresh_building_orders()
	advance_collection()
	for building in buildings:
		if auto_target_limit(building.tile) == 0 or building.targets.is_empty() or tick < building.next_dispatch:
			continue
		building.next_dispatch = tick + TICKS_PER_SECOND
		var targets: Array = building.targets
		var ordered: Array = []
		var offset: int = building.cursor % targets.size()
		for i in range(targets.size()):
			ordered.append(targets[(offset + i) % targets.size()])
		var amount: int = dispatchable_count(building.tile)
		if dispatch(building.owner, building.tile, ordered):
			building.cursor = (offset + amount % targets.size()) % targets.size()

## Shared allocation for manual dispatch and both towers' automatic orders.
## Allocation is equal, with remainder assigned in submitted target order.
func dispatch(actor: int, source: int, targets: Array, unit_type: String = "drone") -> bool:
	if finished or eliminated.has(actor) or not match_players.has(actor):
		return false
	if actor == 0 or source < 0 or source >= tiles.size() or targets.is_empty():
		return false
	if not Content.UNITS.has(unit_type) or unit_type != "drone":
		return false # Other units need their own storage/production before activation.
	var origin: Dictionary = tiles[source]
	if origin.owner != actor or dispatchable_count(source) <= 0:
		return false
	var unique: Array = []
	for target in targets:
		if typeof(target) != TYPE_INT or target < 0 or target >= tiles.size() or target == source or unique.has(target):
			return false
		if not in_range(source, target):
			return false
		unique.append(target)
	var amount: int = dispatchable_count(source)
	origin.count -= amount
	for i in range(unique.size()):
		var count: int = amount / unique.size()
		if i < amount % unique.size():
			count += 1
		if count == 0:
			continue
		var destination: int = unique[i]
		var duration := flight_ticks(hex_distance(origin, tiles[destination]), unit_type)
		fleets.append({"id": next_fleet_id, "owner": actor, "source": source, "target": destination, "count": count, "remaining": count, "unit": unit_type, "start": tick, "duration": duration, "next_arrival": tick + duration})
		next_fleet_id += 1
	domain_event.emit({"type": "dispatch", "actor": actor, "source": source, "targets": unique})
	return true

func advance() -> void:
	if finished:
		return
	tick += 1
	# Deterministic order: growth, collection, tower dispatch, systems, fleet-ID arrivals.
	if tick % TICKS_PER_SECOND == 0:
		for tile in tiles:
			tile.count = grown_count(tile.owner, tile.count, tick - 1, tick)
	advance_buildings()
	for system in systems:
		system.step(self)
	for fleet in fleets:
		if tick >= fleet.next_arrival and fleet.remaining > 0:
			var blocked := false
			for system in systems:
				if system.intercept(self, fleet):
					blocked = true
					break
			if not blocked:
				resolve_impact(fleet.owner, fleet.target, fleet.remaining)
			impacts.append({"id": fleet.id, "target": fleet.target, "source": fleet.source, "owner": fleet.owner, "count": fleet.remaining, "tick": tick, "blocked": blocked})
			fleet.remaining = 0
	impacts = impacts.filter(func(hit): return tick - hit.tick <= 12)
	fleets = fleets.filter(func(f): return f.remaining > 0)
	evaluate_outcome()

func evaluate_outcome() -> void:
	if finished:
		return
	var alive: Array = []
	for player in match_players:
		if eliminated.has(player):
			continue
		var owns_tile := false
		for tile in tiles:
			if tile.owner == player:
				owns_tile = true
				break
		if owns_tile:
			alive.append(player)
		else:
			eliminated.append(player)
			domain_event.emit({"type": "eliminated", "player": player})
	# Eliminated players cannot return through previously dispatched units.
	fleets = fleets.filter(func(f): return not eliminated.has(f.owner))
	if alive.size() <= 1 and match_players.size() >= 2:
		finished = true
		winner = alive[0] if alive.size() == 1 else 0
		domain_event.emit({"type": "match_finished", "winner": winner})

func result_for(player: int) -> String:
	if winner == player and finished:
		return "胜利"
	if eliminated.has(player):
		return "失败"
	return "平局" if finished else ""

func resolve_arrival(actor: int, target: int) -> void:
	resolve_impact(actor, target, 1)

## One projectile carries the whole allocation. Capture arithmetic preserves energy.
func resolve_impact(actor: int, target: int, amount: int) -> void:
	if finished or eliminated.has(actor) or amount <= 0:
		return
	var tile: Dictionary = tiles[target]
	var previous: int = tile.owner
	apply_impact_to(tile, actor, amount)
	if previous != tile.owner:
		var building := building_at(target)
		if not building.is_empty():
			update_building_owner(building, tile.owner)
		domain_event.emit({"type": "capture", "tile": target, "owner": actor})

func snapshot() -> Dictionary:
	return {"impacts": impacts.duplicate(true), "tick": tick, "tiles": tiles.duplicate(true), "fleets": fleets.duplicate(true), "buildings": buildings.duplicate(true), "match_players": match_players.duplicate(), "eliminated": eliminated.duplicate(), "finished": finished, "winner": winner, "next_fleet_id": next_fleet_id}

func restore(state: Dictionary) -> void:
	impacts = state.get("impacts", [])
	tick = state.tick
	tiles = state.tiles
	fleets = state.fleets
	buildings = state.buildings
	match_players = state.match_players
	eliminated = state.eliminated
	finished = state.finished
	winner = state.winner
	next_fleet_id = state.next_fleet_id
