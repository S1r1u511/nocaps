extends SceneTree

## Run start gate: the world waits for the player's first tap on every run.
## Before the first tap nothing scrolls, the cap does not fall, the clock does
## not advance, and "TAP TO FLY" stays up.
##   scripts/run_tests.sh run_start_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("run_start_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://run_start_test_save.json"
	save.selected_community_id = &"mert"
	# Even after the tutorial is seen, every run still waits for the first tap.
	save.tutorial_seen = true

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	run.bind_services(save, null)
	run.set_process(true)

	assert(run._waiting_for_tap, "a fresh run should wait for the first tap")
	assert(run.tap_prompt.visible and run.tap_prompt.text == "TAP TO FLY",
		"TAP TO FLY should show before the first tap")

	var start_distance: float = run.state.distance
	var start_cap_y: float = run.cap.position.y
	for i in range(12):
		await process_frame
	assert(run.state.elapsed == 0.0, "the run clock must not advance before the first tap")
	assert(run.state.distance == start_distance, "the world must not scroll before the first tap")
	assert(is_equal_approx(run.cap.position.y, start_cap_y), "the cap must not fall before the first tap")
	assert(run._spawn.mascots.size() > 0, "the opening mascots stay spawned while waiting")

	run._do_flap()
	assert(not run._waiting_for_tap, "the first tap should release the run")
	await process_frame
	assert(run.state.elapsed > 0.0, "the run should advance after the first tap")

	run.free()
	save.free()
	await process_frame
	print("RUN_START_PASS: the world waits for the first tap on every run")
	quit()
