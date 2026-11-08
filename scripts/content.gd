extends RefCounted
## Content definitions are independent of networking and rendering.
## Footprints use axial hex offsets. Structure IDs are stable save/network IDs.
const UNITS = {
	"drone": {"travel_ticks_per_hex": 5, "arrival_interval": 1, "movement": "air"},
	"infantry": {"travel_ticks_per_hex": 12, "arrival_interval": 2, "movement": "ground"},
}
const BUILDINGS = {
	"command_tower": {"footprint": [Vector2i.ZERO], "system": "auto_dispatch", "cost": 10, "attack_range": 3, "target_limit": -1, "dispatch_reserve": 15},
	"collector": {"footprint": [Vector2i.ZERO], "system": "energy_production", "radius": 0},
	"interceptor": {"footprint": [Vector2i.ZERO], "system": "air_interception", "radius": 2},
	"collection_tower": {"footprint": [Vector2i.ZERO], "system": "energy_collection", "cost": 10, "radius": 1, "reserve": 15, "storage_cap": 150, "target_limit": 1, "dispatch_reserve": 0, "upgrade": {"cost": 20, "radius": 2, "storage_cap": 500}},
	"barracks": {"footprint": [Vector2i.ZERO], "system": "unit_production", "unit": "infantry", "radius": 0},
	"large_structure": {"footprint": [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)], "system": "reserved", "radius": 0},
}
