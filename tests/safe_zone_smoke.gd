extends SceneTree

## Safe landing zone smoke test: simulates 1,000+ mascot segments across random
## seeds and asserts no hazard ever spawns inside a landing spot's safe zone —
## the base clearance on both sides (which includes directly above/below the
## spot) plus the `hazard_safe_after_mascot` window after it. The surprise slam
## obeys the same zone through `Run._surprise_zone_clear` (a run-level rule).
##   scripts/run_tests.sh safe_zone_smoke

const TestEnv := preload("res://tests/test_env.gd")

const SEEDS := 40
const SECONDS := 60.0
const STEP := 1.0 / 30.0
## A landing every 3 s so the run walks through every spacing/speed phase.
const LANDING_EVERY := 3.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("safe_zone_smoke"):
		return
	var tuning := load("res://data/tuning/default_run_tuning.tres") as RunTuning
	assert(tuning != null, "run tuning resource missing")
	assert(tuning.hazard_safe_after_mascot > 0.0, "the safe window must be enabled")

	var mascots_root := Node2D.new()
	var hazards_root := Node2D.new()
	root.add_child(mascots_root)
	root.add_child(hazards_root)

	var segments := 0
	var hazards_checked := 0
	var violations: Array[String] = []
	for seed in range(1, SEEDS + 1):
		var counts: Vector2i = await _simulate(tuning, mascots_root, hazards_root, seed, violations)
		segments += counts.x
		hazards_checked += counts.y

	assert(segments >= 1000, "the test must cover 1,000+ segments (covered %d)" % segments)
	assert(violations.is_empty(),
		"safe zone violations (%d):\n%s" % [violations.size(), "\n".join(violations.slice(0, 5))])
	print("SAFE_ZONE_PASS: %d mascots / %d hazards across %d seeds, zero safe-zone violations" % [
		segments, hazards_checked, SEEDS,
	])
	mascots_root.queue_free()
	hazards_root.queue_free()
	quit()

## One seeded segment of a scrolling run. Returns (mascots, hazards checked).
func _simulate(
	tuning: RunTuning,
	mascots_root: Node2D,
	hazards_root: Node2D,
	seed: int,
	violations: Array[String]
) -> Vector2i:
	var director := SpawnDirector.new()
	director.configure(tuning, mascots_root, hazards_root, 1150.0)
	director.set_communities(null, [])
	var state := RunState.new()
	director.reset(state, seed)

	var known := {}
	var segments := 0
	var checked := 0
	var next_landing := LANDING_EVERY
	for i in range(int(SECONDS / STEP)):
		state.elapsed += STEP
		if state.elapsed >= next_landing:
			state.register_landing()
			next_landing += LANDING_EVERY
		var speed := Difficulty.scroll_speed(tuning, state)
		var step := speed * STEP
		director.scroll(step)
		director.update(STEP, step, state)

		for mascot in director.mascots:
			if not is_instance_valid(mascot):
				continue
			if not known.has(mascot.get_instance_id()):
				known[mascot.get_instance_id()] = true
				segments += 1
		for hazard in director.hazards:
			if not is_instance_valid(hazard):
				continue
			if known.has(hazard.get_instance_id()):
				continue
			known[hazard.get_instance_id()] = true
			checked += 1
			_check_hazard(tuning, director, hazard, speed, seed, violations)
		if i % 300 == 0:
			await process_frame
	return Vector2i(segments, checked)

## The exact spawner rule, re-checked against the live state after the spawn.
func _check_hazard(
	tuning: RunTuning,
	director: SpawnDirector,
	hazard: Hazard,
	speed: float,
	seed: int,
	violations: Array[String]
) -> void:
	var safe := director.safe_after_px(speed)
	for mascot in director.mascots:
		if not is_instance_valid(mascot):
			continue
		var clear := tuning.hazard_clear_from_mascots + mascot.body_radius
		var dx := hazard.position.x - mascot.position.x
		if absf(dx) < clear - 0.01:
			violations.append("seed %d: hazard %.1f inside the %.1f px clearance of mascot %.1f" % [
				seed, hazard.position.x, clear, mascot.position.x,
			])
		elif dx >= 0.0 and dx < clear + safe - 0.01:
			violations.append("seed %d: hazard %.1f inside the %.1f px safe window after mascot %.1f" % [
				seed, hazard.position.x, clear + safe, mascot.position.x,
			])
	var spawn_clear := tuning.hazard_clear_from_next_spawn
	var dxn := hazard.position.x - director._next_mascot_x
	if absf(dxn) < spawn_clear - 0.01:
		violations.append("seed %d: hazard %.1f inside the %.1f px clearance of the next spawn %.1f" % [
			seed, hazard.position.x, spawn_clear, director._next_mascot_x,
		])
	elif dxn >= 0.0 and dxn < spawn_clear + safe - 0.01:
		violations.append("seed %d: hazard %.1f inside the %.1f px safe window after the next spawn %.1f" % [
			seed, hazard.position.x, spawn_clear + safe, director._next_mascot_x,
		])
