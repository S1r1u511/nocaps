extends SceneTree

## Coins smoke test: arcs of 3–5 coins spawn between mascots along a reachable
## path, never on a mascot's head and never inside a hazard; cap contact collects
## them (sparkle tick handled by the run) and they bank as currency only — score,
## combo, contribution, and bests are untouched.
##   scripts/run_tests.sh coins_smoke

const TestEnv := preload("res://tests/test_env.gd")

const SEED := 4242
const SECONDS := 60.0
const STEP := 1.0 / 30.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("coins_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	var tuning := load("res://data/tuning/default_run_tuning.tres") as RunTuning
	assert(tuning != null, "run tuning resource missing")
	assert(tuning.coin_arc_min >= 3 and tuning.coin_pattern_max <= 8, "coin patterns must be 3–8 coins")

	_test_spawning_and_placement(tuning)
	await _test_run_wiring(tuning)

	print("COINS_PASS: arcs, placement, pickup, and currency-only banking verified")
	quit()

## Drives a real SpawnDirector with a fixed seed and checks every arc the Coins
## layer produces: size, head clearance, hazard pruning, and cap pickup.
func _test_spawning_and_placement(tuning: RunTuning) -> void:
	var mascots_root := Node2D.new()
	var hazards_root := Node2D.new()
	var coins := Coins.new()
	root.add_child(mascots_root)
	root.add_child(hazards_root)
	root.add_child(coins)
	coins.configure(tuning)

	var director := SpawnDirector.new()
	director.configure(tuning, mascots_root, hazards_root, 1150.0)
	director.set_communities(null, [])
	var state := RunState.new()
	director.reset(state, SEED)
	coins.reset(SEED)

	var arcs := 0
	for i in range(int(SECONDS / STEP)):
		state.elapsed += STEP
		var speed := Difficulty.scroll_speed(tuning, state)
		var step := speed * STEP
		director.scroll(step)
		coins.scroll(step)
		var before: int = coins.coin_count()
		director.update(STEP, step, state)
		coins.update(STEP, director)
		var spawned: int = coins.coin_count() - before
		if spawned > 0:
			arcs += 1
			assert(spawned <= tuning.coin_pattern_max,
				"pattern %d had %d coins, max %d" % [arcs, spawned, tuning.coin_pattern_max])
		var high_limit := tuning.mascot_line_y - tuning.coin_high_lift - 40.0
		var low_limit := tuning.mascot_line_y + tuning.coin_dip_depth
		for coin_pos in coins.positions():
			assert(coin_pos.y >= high_limit and coin_pos.y <= low_limit,
				"coin at %s is outside the reachable band" % coin_pos)
			for mascot in director.mascots:
				if not is_instance_valid(mascot):
					continue
				assert(not Coins.blocks_coin(mascot, coin_pos, tuning.coin_radius),
					"coin at %s sits on a mascot" % coin_pos)

	assert(arcs >= 3, "the seeded run should produce coin patterns (saw %d)" % arcs)
	assert(coins.pattern_counts.size() >= 3,
		"later gaps should vary patterns (saw %s)" % str(coins.pattern_counts))
	print("COIN_PATTERNS: %s" % str(coins.pattern_counts))

	# A coin survives until a hazard covers it, then the next update clears it.
	assert(coins.coin_count() > 0, "expected live coins before the hazard check")
	var victim: Vector2 = coins.positions()[0]
	var spike := Hazard.new()
	spike.configure_spike(tuning.hazard_radius, victim.y, 0.0)
	spike.position = victim
	hazards_root.add_child(spike)
	director.hazards.append(spike)
	coins.update(0.0, director)
	for remaining in coins.positions():
		assert(remaining.distance_to(victim) > tuning.coin_radius,
			"a coin inside a hazard survived pruning")

	# Cap contact collects and removes the coin.
	assert(coins.coin_count() > 0, "expected a live coin for the pickup check")
	var before_pickup := coins.coin_count()
	var pickup: Vector2 = coins.positions()[0]
	var picked := coins.collect(pickup, tuning.cap_radius)
	assert(picked.size() >= 1, "cap contact should collect a coin")
	assert(coins.coin_count() == before_pickup - picked.size(), "pickup removal mismatch")
	assert(picked.has(pickup), "the touched coin should be the one collected")
	assert(coins.collect(pickup + Vector2(4000.0, 0.0), tuning.cap_radius).is_empty(),
		"distant coins must not collect")

	mascots_root.queue_free()
	hazards_root.queue_free()
	coins.queue_free()

## Run-level wiring: collection increments `state.coins` only, the result payload
## carries `coins` / `coins_total`, and the save keeps the lifetime total.
func _test_run_wiring(tuning: RunTuning) -> void:
	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://nocaps_coins_test_save.json"

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	run.set_process(false)
	run.bind_services(save, null)
	run.tuning.run_seed = SEED
	run.restart()
	# The world waits for the first tap now; release it before driving frames.
	run._do_flap()

	# Drive the run manually so the deterministic seed spawns mascots (and arcs)
	# without waiting on real frame deltas; invincible keeps the run alive.
	run.dev_invincible = true
	for i in range(300):
		run._process(STEP)
	assert(run.coins.coin_count() > 0, "run should spawn coins with a fixed seed")

	run.state.score = 7
	run.state.combo = 0
	var coin_pos: Vector2 = run.coins.positions()[0]
	run.cap.position = coin_pos
	var before_coins: int = run.state.coins
	run._collect_coins()
	assert(run.state.coins == before_coins + tuning.coin_value,
		"cap contact should bank exactly one coin")
	assert(run.state.score == 7, "coins must never change the score")
	assert(run.state.combo == 0, "coins must never change the combo")


	var payload: Dictionary = run._build_result_payload("FELL")
	assert(payload.has("coins"), "result payload must carry this run's coins")
	assert(int(payload["coins"]) == run.state.coins, "payload coins should match the run")
	assert(int(payload["coins_total"]) == run.state.coins, "lifetime total should include this run")
	assert(save.coins_total == run.state.coins, "save should persist coins_total")
	assert(int(payload["contribution"]) == 7,
		"contribution must equal score, never score plus coins")

	# A later run adds to the lifetime total (currency only).
	save.record_coins(4)
	assert(save.coins_total == run.state.coins + 4, "lifetime coins should accumulate")

	# The HUD coin chip appears with the first coin and shows the run's count,
	# in the right-hand column under the score, clear of the crew tag.
	await process_frame
	assert(run._coin_chip.visible, "coin chip should appear after the first coin")
	assert(run._coin_label.text == str(run.state.coins), "coin chip shows the run's coins")
	var chip_rect: Rect2 = run._coin_chip.get_global_rect()
	assert(not chip_rect.intersects(run.score_label.get_global_rect()), "coin chip overlaps the score")
	assert(not chip_rect.intersects(run._tag_panel.get_global_rect()), "coin chip overlaps the crew tag")
	var view_w: float = run.get_viewport_rect().size.x
	assert(chip_rect.end.x <= view_w and chip_rect.position.x >= 0.0, "coin chip off screen: %s in %s" % [chip_rect, view_w])
	run._show_best_ribbon()
	await process_frame
	assert(not chip_rect.intersects(run._best_ribbon.get_global_rect()), "NEW BEST ribbon overlaps the coin chip")
	run._reset_best_ribbon()
	assert(not run._coin_chip.visible, "a new run starts with the coin chip hidden")

	run.queue_free()
	save.queue_free()
	await process_frame
