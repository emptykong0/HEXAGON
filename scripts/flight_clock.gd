extends RefCounted
## Render-time clock. Never reset a projectile's position on a 10 Hz snapshot.
var time := 0.0
var latest_tick := 0
var snapshot_age := 0.0

func reset(tick: int = 0) -> void:
	time = float(tick)
	latest_tick = tick
	snapshot_age = 0.0

func receive(tick: int) -> void:
	if tick > latest_tick:
		latest_tick = tick
		snapshot_age = 0.0

func advance_local(tick: int, remainder: float, ticks_per_second: int) -> void:
	# Called AFTER the simulation loop: tick and remainder belong to the same frame.
	time = tick + remainder * ticks_per_second

func advance_remote(delta: float, ticks_per_second: int) -> void:
	snapshot_age += delta
	var predicted := latest_tick + minf(snapshot_age * ticks_per_second, 2.0)
	# Absorb packet jitter by gently changing speed, never by jumping backwards.
	var speed := clampf(1.0 + (predicted - time) * 0.25, 0.5, 1.5)
	time = minf(time + delta * ticks_per_second * speed, latest_tick + 2.0)
