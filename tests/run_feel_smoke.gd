extends SceneTree

## Gameplay feel/rules smoke test: landing grace + crossing, landing-quality
## scoring, per-run seed handling, speed/spacing ramp guarantees, opening targets,
## target-frequency guard, and hazard pacing/fairness.
##   scripts/run_tests.sh run_feel_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("run_feel_smoke"):
		return
	var tuning := load("res://data/tuning/default_run_tuning.tres") as RunTuning
	assert(tuning != null, "run tuning resource missing")

	_test_landing_resolution()
	_test_scoring_constants()
	_test_difficulty(tuning)
	await _test_spawn_director(tuning)

	print("RUN_FEEL_PASS: landing fairness, scoring, seed, pacing, hazards verified")
	quit()

func _test_landing_resolution() -> void:
	var mascot := MascotActor.new()
	mascot.setup(null, true, Color.WHITE, null, 150.0, 0.42)
	mascot.position = Vector2(400.0, 840.0)
	var band_top := mascot.head_top_y()
	var band_bottom := band_top + mascot.head_band_depth()

	# Normal descent inside the band scores.
	assert(
		Landing.resolve(Vector2(400.0, band_bottom - 4.0), band_top - 30.0, 400.0, 20.0, mascot) == Landing.Outcome.SCORE,
		"descending inside the head band should score"
	)
	# A fast fall that crosses the head top in one frame must not tunnel.
	assert(
		Landing.resolve(Vector2(400.0, band_bottom + 90.0), band_top - 60.0, 1500.0, 20.0, mascot) == Landing.Outcome.SCORE,
		"head-top crossing should catch a fast fall"
	)
	# The small grace above the head top also scores a slow descent.
	assert(
		Landing.resolve(Vector2(400.0, band_top - 23.0), band_top - 30.0, 120.0, 20.0, mascot) == Landing.Outcome.SCORE,
		"grace above the head top should score a slow descent"
	)
	# Rising through the band never scores.
	assert(
		Landing.resolve(Vector2(400.0, band_top - 100.0), band_top + 40.0, -300.0, 20.0, mascot) == Landing.Outcome.NONE,
		"rising through the band must not score"
	)
	# Well below the band is body contact: a bump on your own mascot.
	assert(
		Landing.resolve(mascot.position, mascot.position.y, 500.0, 20.0, mascot) == Landing.Outcome.BUMP,
		"own-mascot body contact should bump"
	)
	# A rival head landing fails even with the crossing check.
	mascot.free()
	var rival := MascotActor.new()
	rival.setup(null, false, Color.WHITE, null, 150.0, 0.42)
	rival.position = Vector2(600.0, 840.0)
	var rival_top := rival.head_top_y()
	assert(
		Landing.resolve(Vector2(600.0, rival_top + 4.0), rival_top - 40.0, 700.0, 20.0, rival) == Landing.Outcome.FAIL,
		"rival head landing should fail"
	)
	rival.free()

func _test_scoring_constants() -> void:
	assert(Scoring.PERFECT_POINTS == 5, "perfect landing should be worth 5")
	assert(Scoring.EDGE_POINTS == 2, "edge landing should be worth 2")
	assert(Scoring.BUMP_POINTS == 1, "bump should be worth 1")
	assert(Scoring.mult_for(4) == 1 and Scoring.mult_for(5) == 2, "x2 at combo 5")
	assert(Scoring.mult_for(10) == 3 and Scoring.mult_for(20) == 4, "x3/x4 at combo 10/20")

	# Skip penalty: -1 with a zero floor, combo/multiplier untouched.
	var skip_state := RunState.new()
	skip_state.score = 3
	skip_state.combo = 2
	skip_state.mult = 2
	skip_state.register_skip()
	assert(skip_state.score == 2, "skip should cost one point")
	assert(skip_state.combo == 2 and skip_state.mult == 2, "skip should keep the combo")
	skip_state.score = 0
	skip_state.register_skip()
	assert(skip_state.score == 0, "skip penalty should never go below zero")

func _test_difficulty(tuning: RunTuning) -> void:
	var state := RunState.new()
	# playtest_v05: the opening eases in from `speed_ease_in_start`, then ramps.
	assert(
		is_equal_approx(Difficulty.scroll_speed(tuning, state), tuning.base_scroll_speed * tuning.speed_ease_in_start),
		"speed should start eased down by speed_ease_in_start"
	)
	state.elapsed = tuning.speed_ease_in_seconds
	var ramped := minf(
		tuning.base_scroll_speed * (1.0 + tuning.speed_gain_per_second * state.elapsed),
		tuning.base_scroll_speed * tuning.max_scroll_multiplier
	)
	assert(
		is_equal_approx(Difficulty.scroll_speed(tuning, state), ramped),
		"speed should be the full (un-eased) ramp when the ease-in window ends"
	)
	state.landings = 4
	var mid := Difficulty.scroll_speed(tuning, state)
	assert(mid > tuning.base_scroll_speed, "speed should ramp with landings")
	state.landings = 200
	state.elapsed = 200.0
	var cap := tuning.base_scroll_speed * tuning.max_scroll_multiplier
	assert(
		is_equal_approx(Difficulty.scroll_speed(tuning, state), cap),
		"speed ramp should cap at %s" % cap
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var early := Difficulty.mascot_gap(tuning, RunState.new(), tuning.base_scroll_speed, false, rng)
	assert(
		early >= tuning.gap_time_early_min * tuning.base_scroll_speed
		and early <= tuning.gap_time_early_max * tuning.base_scroll_speed,
		"early gap should match its time budget"
	)

	var late_state := RunState.new()
	late_state.landings = tuning.gap_phase_late_landings
	var late := Difficulty.mascot_gap(tuning, late_state, cap, false, rng)
	assert(
		late >= tuning.gap_time_late_min * cap and late <= tuning.gap_time_late_max * cap,
		"late gap should match its time budget at the speed cap"
	)
	assert(late > early, "pixel spacing should grow as speed rises")
	assert(early / tuning.base_scroll_speed >= 1.2, "time between mascots should stay readable early")
	assert(late / cap >= 1.0, "time between mascots should stay readable at cap")

	var opening := Difficulty.mascot_gap(tuning, RunState.new(), tuning.base_scroll_speed, true, rng)
	assert(
		opening >= tuning.gap_time_opening_min * tuning.base_scroll_speed
		and opening <= tuning.gap_time_opening_max * tuning.base_scroll_speed,
		"opening gap should match its time budget"
	)

func _test_spawn_director(tuning: RunTuning) -> void:
	var mascots_root := Node2D.new()
	var hazards_root := Node2D.new()
	root.add_child(mascots_root)
	root.add_child(hazards_root)

	var director := SpawnDirector.new()
	director.configure(tuning, mascots_root, hazards_root, 1150.0)
	director.set_communities(null, [])
	var state := RunState.new()
	director.reset(state, 1337)
	assert(director._rng.seed == 1337, "fixed seed should be applied")
	assert(director.mascots.size() == 1 and director.mascots[0].is_target, "first mascot is always the target")

	# The opening guarantees `opening_targets` own-community mascots back-to-back.
	var seen: Array[String] = []
	var guard := 0
	while director._opening_left > 0 and guard < 400:
		state.elapsed += 0.1
		director.scroll(30.0)
		director.update(0.1, 30.0, state)
		for mascot in director.mascots:
			if is_instance_valid(mascot) and not seen.has(mascot.name):
				seen.append(mascot.name)
		guard += 1
	assert(director._opening_left == 0, "opening targets should spawn")
	for i in range(tuning.opening_targets):
		assert(
			i < seen.size() and seen[i].begins_with("Target"),
			"opening mascot %d should be the player's own (saw %s)" % [i, seen]
		)

	# With no unclaimed target ahead, the rival cap forces the next target.
	director._opening_left = 0
	for mascot in director.mascots:
		if is_instance_valid(mascot):
			mascot.claimed = true
	director._rivals_since_target = 999
	director._time_since_target = 0.0
	director._distance_since_target = 0.0
	assert(director._next_mascot_is_target(state), "max rivals between targets should force a target")

	# An unclaimed target still ahead blocks a second one.
	director._spawn_mascot(tuning.cap_x + 300.0, true)
	assert(not director._next_mascot_is_target(state), "an unclaimed target ahead should block target spam")

	var other := SpawnDirector.new()
	other.configure(tuning, mascots_root, hazards_root, 1150.0)
	other.set_communities(null, [])
	other.reset(RunState.new(), 0)
	assert(other._rng.seed != 0, "random runs should not share the fixed seed")
	var third := SpawnDirector.new()
	third.configure(tuning, mascots_root, hazards_root, 1150.0)
	third.set_communities(null, [])
	third.reset(RunState.new(), 0)
	assert(other._rng.seed != third._rng.seed, "random runs should get fresh seeds")

	# Hazards stay suppressed during the opening window.
	state.elapsed = tuning.hazard_start_delay - 0.5
	for i in range(20):
		director.scroll(30.0)
		director.update(0.1, 30.0, state)
	assert(director.hazards.is_empty(), "no hazards should spawn during the opening")

	# Once active, hazards appear, respect the cap, and keep clearance.
	state.elapsed = tuning.hazard_start_delay + 0.5
	var attempts := 0
	while director.hazards.is_empty() and attempts < 400:
		state.elapsed += 0.1
		director.scroll(30.0)
		director.update(0.1, 30.0, state)
		attempts += 1
	assert(not director.hazards.is_empty(), "hazards should spawn after the opening")
	assert(
		director.hazards.size() <= tuning.hazard_max_concurrent,
		"hazard concurrency should stay within the cap"
	)

	for hazard in director.hazards:
		if not is_instance_valid(hazard):
			continue
		for mascot in director.mascots:
			if not is_instance_valid(mascot):
				continue
			var spacing := absf(hazard.position.x - mascot.position.x)
			assert(
				spacing >= tuning.hazard_clear_from_mascots + mascot.body_radius - 0.01,
				"hazard spawned too close to a mascot"
			)
		for other_hazard in director.hazards:
			if hazard == other_hazard or not is_instance_valid(other_hazard):
				continue
			if hazard.kind == Hazard.Kind.CEIL or other_hazard.kind == Hazard.Kind.CEIL:
				continue
			var close_x := absf(hazard.position.x - other_hazard.position.x) < tuning.hazard_min_spacing_x
			var close_y := absf(hazard.position.y - other_hazard.position.y) < tuning.hazard_min_spacing_y
			assert(not (close_x and close_y), "hazards spawned on top of each other")

	mascots_root.queue_free()
	hazards_root.queue_free()
	await process_frame
