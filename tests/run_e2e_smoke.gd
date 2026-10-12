extends SceneTree

## End-to-end run cross-check: start HUD, first-run tutorial, pause/back overlay,
## the YOURS hint on the first 3 own mascots (and that later mascots keep their
## fit/cap state), cap seating (perfect only), hazard death -> Result, live NEW
## BEST, and a clean restart.
##   scripts/run_tests.sh run_e2e_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("run_e2e_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://nocaps_e2e_test_save.json"

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	run.set_process(false)
	run.tuning.fail_delay = 0.0
	run.bind_services(save, null)

	_check_start_and_tutorial(run, save)
	_check_pause_and_back(run)
	_check_yours_hint(run)
	_check_cap_seating(run)
	await _check_hazard_death(run, save)
	_check_new_best(run, save)
	_check_restart(run, save)

	run.queue_free()
	save.queue_free()
	await process_frame
	print("RUN_E2E_PASS: tutorial, pause/back, YOURS hint, cap seating, hazard death, NEW BEST, restart")
	quit()

func _check_start_and_tutorial(run: Node, save: SaveManager) -> void:
	save.tutorial_seen = false
	run.restart()
	assert(run.state.score == 0 and run.state.alive, "a run must start at zero and alive")
	assert(run.cap.position == Vector2(run.tuning.cap_x, run.tuning.start_y), "cap must start at the authored position")
	assert(run._tag_panel.visible and run._tag_name_label.text.begins_with("FOR "), "crew tag missing at start")
	assert(run._goal_popup.visible, "crew-goal popup should show at run start")

	# First run: TAP TO FLY -> flap swaps to the land-only hint -> hint expires
	# and the seen flag persists.
	assert(run._tutorial_stage == 1 and run.tap_prompt.visible, "first-run tutorial should prompt a tap")
	assert(run.tap_prompt.text == "TAP TO FLY", "unexpected first tutorial text: %s" % run.tap_prompt.text)
	run._do_flap()
	assert(run._tutorial_stage == 2 and run.tap_prompt.text == "LAND ONLY ON YOUR MASCOT",
		"flapping should swap to the land-only hint")
	run._update_tutorial(3.6)
	assert(run._tutorial_stage == 0 and not run.tap_prompt.visible, "the tutorial hint should expire")
	assert(save.tutorial_seen, "finishing the tutorial must persist tutorial_seen")

	# Every run waits for the first tap; a seen tutorial only skips the land-only
	# hint, so TAP TO FLY still shows and the stage stays 0 until the tap.
	run.restart()
	assert(run._waiting_for_tap and run.tap_prompt.visible, "every run must wait for the first tap")
	assert(run._tutorial_stage == 0, "a seen tutorial must not replay the land-only hint")
	assert(run.tap_prompt.text == "TAP TO FLY", "waiting shows the tap prompt: %s" % run.tap_prompt.text)
	run._do_flap()
	assert(not run._waiting_for_tap and run._tutorial_stage == 0 and not run.tap_prompt.visible,
		"a seen tutorial goes straight into the run after the tap")

func _check_pause_and_back(run: Node) -> void:
	run._resume()
	run._pause()
	assert(run._paused and run.pause_overlay.visible, "pause must show the overlay")
	run._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(not run._paused and not run.pause_overlay.visible, "back must resume when paused")
	run._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert(run._paused and run.pause_overlay.visible, "back must pause a live run")
	run._resume()
	assert(not run._paused, "resume must clear the pause")
	run.set_process(false)

## The YOURS tag belongs to the first three own-crew mascots only; later ones
## must lose only the tag, never their authored sprite, fit, or cap state.
func _check_yours_hint(run: Node) -> void:
	run.restart()
	var x: float = run.tuning.cap_x + 400.0
	for i in range(4):
		run._spawn._spawn_mascot(x, true)
		x += 700.0
	run._apply_yours_tag_hint()
	assert(run._tag_hinted_targets == 5, "expected 5 own-crew mascots, saw %d" % run._tag_hinted_targets)
	for i in range(run._spawn.mascots.size()):
		var mascot: MascotActor = run._spawn.mascots[i]
		if not is_instance_valid(mascot) or not mascot.is_target:
			continue
		var expected := i < 3
		assert(mascot.show_yours_tag == expected,
			"mascot %d YOURS tag should be %s" % [i, expected])
	# Regression: mascots past the hint keep their full authored state.
	var later: MascotActor = run._spawn.mascots[3]
	assert(later.definition != null and later._sprite != null and later._cap_sprite != null,
		"the YOURS hint must not wipe a mascot's sprite/cap references")
	later.claim(true)
	assert(later.claimed and later._cap_sprite.visible,
		"a hinted-out mascot must still be able to seat its cap")

func _check_cap_seating(run: Node) -> void:
	run.restart()
	var perfect_target := _first_unclaimed_target(run)
	assert(perfect_target != null, "no target to claim")
	run.cap.velocity_y = 320.0
	run.cap.position = Vector2(perfect_target.head_center_x(), perfect_target.head_top_y() - 5.0)
	run._resolve_landings()
	assert(perfect_target.claimed and perfect_target.cap_seated, "a centered landing should seat the cap")
	assert(perfect_target._cap_sprite.visible, "a perfectly claimed mascot must show its cap")
	assert(perfect_target._cap_sprite.position == MascotFit.cap_local_position(
		perfect_target.definition, perfect_target._content_size, perfect_target._scale),
		"the seated cap must use the authored fit anchor")

	# Edge landing: claims and scores, but leaves the mascot bare.
	run.restart()
	var edge_target := _first_unclaimed_target(run)
	assert(edge_target != null, "no target for the edge landing")
	run.cap.velocity_y = 320.0
	run.cap.position = Vector2(
		edge_target.head_center_x() + edge_target.head_half_width() * 0.8,
		edge_target.head_top_y() - 5.0
	)
	var before: int = run.state.score
	run._resolve_landings()
	assert(edge_target.claimed, "an edge landing should still claim the mascot")
	assert(not edge_target.cap_seated, "an edge landing must not seat the cap")
	assert(not edge_target._cap_sprite.visible, "an edge-claimed mascot must stay bare")
	assert(run.state.score == before + Scoring.EDGE_POINTS,
		"edge landing should score %d" % Scoring.EDGE_POINTS)

func _check_hazard_death(run: Node, save: SaveManager) -> void:
	run.restart()
	var captured: Array = []
	run.navigate.connect(func(screen: StringName, payload: Dictionary) -> void:
		captured.append({"screen": screen, "payload": payload}))
	var spike := Hazard.new()
	spike.configure_spike(run.tuning.hazard_radius, run.tuning.mascot_line_y, 0.0)
	spike.position = run.cap.position + Vector2(10.0, 0.0)
	run.hazards_root.add_child(spike)
	run._spawn.hazards.append(spike)
	run._resolve_hazards()
	assert(run._failed and not run.state.alive, "hazard contact must end the run")
	assert(run.state.fail_reason == "SPIKED!", "unexpected hazard reason: %s" % run.state.fail_reason)
	await process_frame
	await process_frame
	assert(captured.size() == 1 and captured[0]["screen"] == &"result", "hazard death must reach Result")
	assert(captured[0]["payload"].has("coins"), "result payload must carry coins")
	assert(save.runs_played >= 1, "the finished run must be recorded in the save")

func _check_new_best(run: Node, save: SaveManager) -> void:
	save.best_score = 5
	run.restart()
	assert(run._best_at_start == 5, "restart should snapshot the persisted best")
	run.state.score = 6
	run._update_hud()
	assert(run._new_best and run._best_ribbon.visible, "passing the persisted best must show NEW BEST")
	assert(run.score_label.get_theme_color("font_color") == Color("ffd23f"), "new-best score must be GOLD")

func _check_restart(run: Node, save: SaveManager) -> void:
	run.state.score = 9
	run.state.elapsed = 12.0
	run.state.coins = 3
	run.restart()
	assert(run.state.score == 0 and run.state.elapsed == 0.0 and run.state.coins == 0,
		"restart must reset score, timer, and coins")
	assert(run.effects._popups.is_empty(), "restart must clear feedback popups")
	assert(run.coins.coin_count() == 0, "restart must clear coins")
	assert(not run._new_best and not run._best_ribbon.visible, "restart must clear NEW BEST")
	assert(run.score_label.get_theme_color("font_color") == Color("fff4dc"), "restart must restore CREAM score")

func _first_unclaimed_target(run: Node) -> MascotActor:
	for mascot in run._spawn.mascots:
		if is_instance_valid(mascot) and mascot.is_target and not mascot.claimed:
			return mascot
	return null
