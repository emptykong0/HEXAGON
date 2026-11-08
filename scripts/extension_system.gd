extends RefCounted
## Register instances in Simulation.systems on the host only.
## Persistent results must live in snapshot-covered model state.
func step(_simulation: RefCounted) -> void:
	pass

## Called before each scheduled arrival. true consumes the entire energy projectile.
## Continuous path/area interception can be implemented in step().
func intercept(_simulation: RefCounted, _fleet: Dictionary) -> bool:
	return false
