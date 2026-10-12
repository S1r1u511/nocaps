extends SceneTree

## Phase 3.6 core-loop smoke test: the run boots, a clean own-mascot landing scores
## a perfect +5, spawns a landing burst, and bounces; rival and ground contact fail
## and reach the Result screen after the failure beat; best score is persisted.
##   scripts/run_tests.sh run_core_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("run_core_smoke"):
		return
	# Keep the smoke test silent so synthesized audio buffers never allocate.
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://nocaps_test_save.json"
	save.best_score = 0

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	run.set_process(false)
	run.bind_services(save, null)
	run.tuning.fail_delay = 0.0

	assert(run.tuning != null, "run tuning resource missing")
	assert(run.state.score == 0, "run should start at 0")

	var target: MascotActor = null
	for mascot in run._spawn.mascots:
		if mascot.is_target:
			target = mascot
			break
	assert(target != null, "no target mascot spawned at reset")
	assert(target._sprite.visible and target._sprite.texture != null, "target should render community art")
	assert(not target._cap_sprite.visible, "cap should be hidden before a claim")

	# The in-flight cap matches the target community's seated cap width.
	var expected_cap_width := MascotFit.seated_cap_width(run.target_community.mascot, run.tuning.mascot_world_size)
	assert(expected_cap_width > 0.0, "seated cap width should be positive for a textured community")
	assert(absf(run.cap.world_width - expected_cap_width) < 0.01, "in-flight cap width should match the seated cap width")

	# Clean landing on the head, descending: scores a perfect +5, claims, bursts, bounces.
	run.cap.velocity_y = 300.0
	run.cap.position = Vector2(target.head_center_x(), target.head_top_y() - 5.0)
	run._resolve_landings()
	assert(run.state.score == 5, "centered own-mascot landing should score a perfect +5")
	assert(target.claimed, "landing did not claim the target")
	assert(target._cap_sprite.visible, "claimed target should show the fitted cap")
	assert(run.cap.velocity_y < 0.0, "landing did not bounce the cap")
	assert(run.effects._dots.size() >= 1, "landing should spawn effect dots")
	assert(run.effects._popups.size() >= 1, "landing should spawn a score popup")

	# Repeated body contact must score only once (bump cooldown), not per frame.
	run._spawn._spawn_mascot(700.0, true)
	var fresh: MascotActor = run._spawn.mascots.back()
	run.cap.velocity_y = 0.0
	run.cap.position = fresh.position
	var before_bump: int = run.state.score
	run._resolve_landings()
	run._resolve_landings()
	assert(run.state.score == before_bump + 1, "repeated body contact should bump only once")

	# Combo scoring: multipliers at 5/10/20, and a bump resets the combo.
	var scoring_state := RunState.new()
	for i in range(5):
		scoring_state.register_landing()
	assert(scoring_state.combo == 5, "combo should reach 5")
	assert(scoring_state.mult == 2, "combo 5 should be x2")
	assert(scoring_state.score == 30, "five perfect landings should score 5+5+5+5+10=30")
	scoring_state.register_bump()
	assert(scoring_state.combo == 0 and scoring_state.mult == 1, "bump should reset the combo")
	assert(scoring_state.score == 31, "bump should add +1")

	# Landing resolution returns BUMP for own-mascot body contact.
	var own := MascotActor.new()
	own.setup(null, true, Color.WHITE, null, run.tuning.mascot_world_size, run.tuning.mascot_body_radius_ratio)
	own.position = Vector2(500.0, run.tuning.mascot_line_y)
	assert(Landing.resolve(own.position, own.position.y, 0.0, run.tuning.cap_radius, own) == Landing.Outcome.BUMP, "own body should bump")
	own.free()

	# Rival contact ends the run and reaches Result after the failure beat.
	var captured: Array = []
	run.navigate.connect(func(screen: StringName, payload: Dictionary) -> void:
		captured.append({"screen": screen, "payload": payload}))
	var rival := MascotActor.new()
	rival.setup(null, false, run.tuning.rival_color, null, run.tuning.mascot_world_size, run.tuning.mascot_body_radius_ratio)
	rival.position = Vector2(run.cap.position.x + 400.0, run.tuning.mascot_line_y)
	run.mascots_root.add_child(rival)
	run._spawn.mascots.append(rival)
	run.cap.velocity_y = 0.0
	run.cap.position = rival.position
	run._resolve_landings()
	assert(run._failed, "rival contact did not end the run")
	assert(run.state.fail_reason == "WRONG MASCOT!", "unexpected rival fail reason: %s" % run.state.fail_reason)
	assert(save.best_score == 6, "best score was not persisted")
	await process_frame
	await process_frame
	assert(captured.size() == 1 and captured[0]["screen"] == &"result", "failure did not navigate to result")
	assert(captured[0]["payload"]["score"] == 6, "result payload score mismatch")
	assert(captured[0]["payload"]["new_best"] == true, "first run should be a new best")
	assert(captured[0]["payload"].has("survival_seconds"), "result payload should carry the survival time")

	# A fresh run resets state, and ground contact ends it.
	run.restart()
	assert(run.state.score == 0 and run.state.alive, "restart did not reset the run")
	run.cap.position.y = run._ground_y + run.tuning.cap_radius
	run._check_ground()
	assert(run._failed and run.state.fail_reason == "FELL", "ground contact did not end the run")

	# Skip penalty: passing an own-crew mascot without landing costs a point
	# after the grace window, at most once per mascot.
	run.restart()
	run.state.elapsed = run.tuning.skip_penalty_grace + 0.5
	run.state.score = 4
	var skipped: MascotActor = null
	for mascot in run._spawn.mascots:
		if is_instance_valid(mascot) and mascot.is_target and not mascot.claimed:
			skipped = mascot
			break
	assert(skipped != null, "no unclaimed own-crew mascot to skip")
	skipped.position.x = run.cap.position.x - skipped.body_radius - run.tuning.cap_radius - 10.0
	run._check_skips()
	assert(run.state.score == 3, "skipping an own-crew mascot should cost one point")
	assert(skipped.has_meta("nocaps_skip_penalized"), "skip should mark the mascot")
	run._check_skips()
	assert(run.state.score == 3, "a mascot should be penalized at most once")

	# The grace window suppresses the penalty.
	var grace_target := _add_mascot(run, true, run.cap.position.x - 300.0)
	run.state.elapsed = run.tuning.skip_penalty_grace - 0.5
	run.state.score = 4
	run._check_skips()
	assert(run.state.score == 4, "no skip penalty inside the grace window")

	# Other crews' mascots are never penalized.
	var rival_skip := _add_mascot(run, false, run.cap.position.x - 300.0)
	run.state.score = 4
	run._check_skips()
	assert(run.state.score == 4, "rivals should never be skip-penalized")
	assert(not rival_skip.has_meta("nocaps_skip_penalized"), "rival should not be marked as skipped")

	# The penalty never goes below zero.
	run.state.elapsed = run.tuning.skip_penalty_grace + 0.5
	run.state.score = 0
	run._check_skips()
	assert(run.state.score == 0, "the score floor is zero")
	assert(grace_target.has_meta("nocaps_skip_penalized"), "grace target should be penalized now")
	grace_target.queue_free()
	rival_skip.queue_free()

	run.free()
	save.free()
	print("RUN_CORE_PASS: core loop scores, bursts, fails, and persists best")
	quit()

func _add_mascot(run: Node, is_target: bool, x: float) -> MascotActor:
	var mascot := MascotActor.new()
	mascot.setup(null, is_target, Color.WHITE, null, run.tuning.mascot_world_size, run.tuning.mascot_body_radius_ratio)
	mascot.position = Vector2(x, run.tuning.mascot_line_y)
	run.mascots_root.add_child(mascot)
	run._spawn.mascots.append(mascot)
	return mascot
