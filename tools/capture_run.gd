extends SceneTree

## Deterministic run captures for gameplay review. Needs a real renderer (not
## --headless), because the capture reads the root viewport texture.
##
##   Godot --path . --script res://tools/capture_run.gd -- \
##     --mode=start --out=.build/reports/gameplay-polish/run_start.png
##
## Modes: start, tutorial, perfect, edge, coins, skip, hazard, death, newbest,
## pause, restart. Uses a throwaway save next to the capture and a fixed run seed
## so repeated captures are comparable at 720x1560.

const SIZE := Vector2i(720, 1560)
const SEED := 20261001
const STEP := 1.0 / 60.0
const CAPTURE_DIR := "res://.build/reports/gameplay-polish"

func _initialize() -> void:
	call_deferred("capture")

var _options: Dictionary = {}

func capture() -> void:
	var options := _parse_args()
	_options = options
	var mode := str(options.get("mode", "start"))
	var out := str(options.get("out", "%s/run_%s.png" % [CAPTURE_DIR, mode]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	root.size = SIZE
	await process_frame

	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	var save := SaveManager.new()
	save.name = "CaptureSave"
	save.save_path = "user://capture_%s_save.json" % mode
	root.add_child(save)
	if mode != "tutorial":
		save.tutorial_seen = true
	save.best_score = 4 if mode == "newbest" else 50

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	run.set_process(false)
	run.bind_services(save, null)
	run.tuning.run_seed = SEED
	run.tuning.camera_zoom = 0.88
	run.restart()

	_setup(run, save, mode)
	for i in range(int(options.get("hold", 12))):
		await process_frame

	var image: Image = root.get_viewport().get_texture().get_image()
	var error := image.save_png(out)
	if error != OK:
		push_error("capture failed to write %s (%s)" % [out, error_string(error)])
	print("CAPTURE_SAVED %s %s" % [out, image.get_size()])
	quit()

func _setup(run: Node, save: SaveManager, mode: String) -> void:
	match mode:
		"start":
			_advance(run, 0.35)
		"tutorial":
			save.tutorial_seen = false
			run.restart()
			_advance(run, 0.35)
		"perfect":
			_land_on(run, true)
		"edge":
			_land_on(run, false)
		"coinchip":
			# HUD with the coin chip and NEW BEST stacked in the right column.
			run.dev_invincible = true
			_advance(run, 6.0)
			run.state.coins = 12
			run._update_coin_chip()
			run.state.score = 60
			run._update_new_best()
			_advance(run, 0.4)
		"late":
			# --seconds=N: an invincible run N seconds in (coin patterns, pacing).
			run.dev_invincible = true
			_advance(run, float(_options.get("seconds", 30)))
		"coins":
			run.dev_invincible = true
			for i in range(2400):
				run._process(STEP)
				if _coin_on_screen(run):
					break
			_frame_nearest_coins(run)
		"skip":
			run.state.elapsed = run.tuning.skip_penalty_grace + 1.0
			run.state.score = 9
			var skipped := _first_unclaimed_target(run)
			if skipped != null:
				skipped.position.x = run.cap.position.x \
					- skipped.body_radius - run.tuning.cap_radius - 14.0
				run._check_skips()
			_advance(run, 0.12)
		"hazard":
			run.dev_invincible = true
			run.state.elapsed = run.tuning.hazard_start_delay
			for i in range(3000):
				run._process(STEP)
				if _hazard_on_screen(run):
					break
			_frame_nearest_hazard(run)
		"death":
			run.state.score = 12
			run.cap.position = Vector2(run.cap.position.x, run._ground_y + 40.0)
			run._check_ground()
			_advance(run, 0.3)
		"newbest":
			run.state.score = 6
			run._update_hud()
			_advance(run, 0.4)
		"pause":
			_advance(run, 0.3)
			run._pause()
		"restart":
			_advance(run, 0.3)
			run.state.score = 9
			run._update_hud()
			run.restart()
			_advance(run, 0.2)

func _advance(run: Node, seconds: float) -> void:
	for i in range(int(seconds / STEP)):
		run._process(STEP)

## Positions the cap on the next target's head, centered for a perfect landing
## or offset toward the head edge for an edge landing.
func _land_on(run: Node, centered: bool) -> void:
	var mascot := _first_unclaimed_target(run)
	if mascot == null:
		return
	var offset := 0.0 if centered else mascot.head_half_width() * 0.82
	run.cap.velocity_y = 320.0
	run.cap.position = Vector2(mascot.head_center_x() + offset, mascot.head_top_y() - 5.0)
	run._resolve_landings()
	# Let the perfect/combo popup and the cap pulse read on the capture.
	for i in range(8):
		run.effects._process(1.0 / 60.0)

func _first_unclaimed_target(run: Node) -> MascotActor:
	for mascot in run._spawn.mascots:
		if is_instance_valid(mascot) and mascot.is_target and not mascot.claimed:
			return mascot
	return null

## True when at least one coin sits in the visible middle band.
func _coin_on_screen(run: Node) -> bool:
	for pos in run.coins.positions():
		var screen_x: float = run._world_to_screen(pos).x
		if screen_x > 80.0 and screen_x < 640.0 and pos.y > 400.0 and pos.y < 1200.0:
			return true
	return false

func _frame_nearest_coins(run: Node) -> void:
	var positions: Array[Vector2] = run.coins.positions()
	if positions.is_empty():
		return
	var best: Vector2 = positions[0]
	for pos in positions:
		if absf(pos.x - 360.0) < absf(best.x - 360.0):
			best = pos
	run.cap.position = Vector2(best.x, best.y + 90.0)
	run.cap.velocity_y = -120.0

## True when at least one hazard sits in the visible middle band.
func _hazard_on_screen(run: Node) -> bool:
	for hazard in run._spawn.hazards:
		if not is_instance_valid(hazard):
			continue
		var screen_x: float = run._world_to_screen(hazard.position).x
		if screen_x > 90.0 and screen_x < 640.0:
			return true
	return false

func _frame_nearest_hazard(run: Node) -> void:
	var best: Hazard = null
	for hazard in run._spawn.hazards:
		if not is_instance_valid(hazard):
			continue
		if best == null or absf(hazard.position.x - 360.0) < absf(best.position.x - 360.0):
			best = hazard
	if best != null:
		run.cap.position = Vector2(best.position.x - 150.0, run.tuning.mascot_line_y - 40.0)
		run.cap.velocity_y = -80.0

func _parse_args() -> Dictionary:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var text := argument.trim_prefix("--")
		if text.contains("="):
			var parts := text.split("=", true, 1)
			options[parts[0]] = parts[1]
		else:
			options[text] = true
	return options
