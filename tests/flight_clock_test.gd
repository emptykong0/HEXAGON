extends SceneTree
const Clock = preload("res://scripts/flight_clock.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Exercise the actual game loop, crossing simulation boundaries at many frame rates.
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for fps in [30, 60, 120, 144]:
		game.start_pve()
		game.transition.kill()
		game.transitioning = false
		var elapsed := 0.0
		var previous := 0.0
		for i in range(fps):
			var dt: float = 1.0 / fps
			elapsed += dt
			game._process(dt)
			var now: float = game.flight_clock.time
			check(is_equal_approx(now, elapsed * 10), "local flight follows elapsed render time at %s fps" % fps)
			check(now > previous and absf(now - previous - dt * 10) < 0.00001, "no backward or double-sized step at tick boundary")
			previous = now
	var clock = Clock.new()
	var packets := [[0.095, 1], [0.21, 2], [0.29, 3], [0.45, 4], [0.51, 5], [0.72, 7], [0.82, 8]]
	var next_packet := 0
	var previous := 0.0
	for i in range(240):
		var elapsed := float(i + 1) / 120
		while next_packet < packets.size() and elapsed >= packets[next_packet][0]:
			clock.receive(packets[next_packet][1])
			next_packet += 1
		clock.advance_remote(1.0 / 120, 10)
		check(clock.time >= previous and clock.time - previous <= 0.12501, "packet jitter cannot reverse or teleport flight")
		check(clock.time <= clock.latest_tick + 2.0, "prediction is bounded during a network stall")
		previous = clock.time
	clock.receive(2)
	check(clock.latest_tick == 8, "stale snapshots cannot rewind clock")
	clock.receive(30)
	clock.advance_remote(1.0 / 120, 10)
	check(clock.time >= previous and clock.time - previous <= 0.12501, "recovery from delayed packets changes speed without a jump")
	clock.reset()
	check(clock.time == 0 and clock.latest_tick == 0, "new session resets render clock")
	game.queue_free()
	print("Flight clock tests: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
