extends SceneTree

## HUD layout smoke test: at 720x1280 and 720x1560 the v3 run-HUD zones (crew
## tag, score column, opening crew-goal popup) are disjoint and sit at the
## mockup-derived anchors; the NEW BEST ribbon toggles with the live best; and
## the Result screen's "Survived m:ss" line neither overlaps nor moves PLAY
## AGAIN. Prints every rect so a failure can be diagnosed without a capture.
##   scripts/run_tests.sh hud_layout_smoke

const TestEnv := preload("res://tests/test_env.gd")

const SIZES := [Vector2i(720, 1280), Vector2i(720, 1560)]
const SURVIVAL := 84.0

var _retry_positions: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("hud_layout_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false
	# Result moments dock into the page and would confound the button-position
	# comparison; the layout contract must hold with none of them showing.
	Moments.set_enabled(false)

	for size in SIZES:
		root.size = size
		await process_frame
		await _check_run_hud(size)
		await _check_result_screen(size)

	# Popup-rule checks run last: they need a live run and must not perturb the
	# Result-page measurements above.
	await _check_popup_layout()

	root.size = Vector2i(720, 1280)
	print("HUD_LAYOUT_PASS: run + result HUD rects are disjoint at 720x1280 and 720x1560")
	quit()

## A throwaway run just for the popup-overlap rules, so the main HUD checks run
## from the exact same state they always did.
func _check_popup_layout() -> void:
	var save := SaveManager.new()
	save.name = "PopupSave"
	root.add_child(save)
	save.save_path = "user://nocaps_popup_test_save.json"
	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	run.set_process(false)
	run.bind_services(save, null)
	_check_popup_rules(run)
	run.queue_free()
	save.queue_free()
	await process_frame

## Assertion failures in `--script` runs are printed but do not stop the script,
## so critical checks also fail the process explicitly.
func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("HUD_LAYOUT_FAIL: %s" % message)
	quit(1)

func _check_run_hud(size: Vector2i) -> void:
	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://nocaps_test_save.json"

	var run: Node = load("res://scenes/run.tscn").instantiate()
	root.add_child(run)
	await process_frame
	await process_frame
	run.set_process(false)
	# Snap the run-start pop tweens (score bump, goal pop-in) to their end state so
	# the geometry assertions measure the layout, not the animation.
	run.score_label.scale = Vector2.ONE
	run._goal_popup.scale = Vector2.ONE
	run._goal_popup.modulate.a = 1.0
	run.bind_services(save, null)

	# v3 anchors (docs/mockups/v3/README.md): tag left 30 / top 41; goal popup
	# left-aligned under it with a 26 px gap, 278 px wide; score right 33 and its
	# rect top at 13 so the ink lands on the mockup's 44.
	var tag_rect: Rect2 = run._tag_panel.get_global_rect()
	_require(absf(tag_rect.position.x - 30.0) < 1.0, "crew tag left should be 30 (got %s)" % tag_rect.position.x)
	_require(absf(tag_rect.position.y - 41.0) < 1.0, "crew tag top should be 41 (got %s)" % tag_rect.position.y)
	_require(run._goal_popup.visible, "crew-goal popup should be visible at run start")
	var goal_rect: Rect2 = run._goal_popup.get_global_rect()
	_require(absf(goal_rect.position.x - tag_rect.position.x) < 0.5,
		"crew-goal popup must be left-aligned with the tag (got %s vs %s)" % [goal_rect.position.x, tag_rect.position.x])
	_require(absf(goal_rect.position.y - (tag_rect.end.y + 26.0)) < 1.0,
		"crew-goal popup gap should be 26 px (got %s)" % (goal_rect.position.y - tag_rect.end.y))
	_require(absf(goal_rect.size.x - 278.0) < 1.0,
		"crew-goal popup width should be 278 (got %s)" % goal_rect.size.x)
	var score_rect: Rect2 = run.score_label.get_global_rect()
	_require(absf(score_rect.end.x - (float(size.x) - 33.0)) < 1.0,
		"score right edge should be 33 px from the right (got %s)" % (float(size.x) - score_rect.end.x))
	_require(absf(score_rect.position.y - 13.0) < 1.0,
		"score rect top should be 13 (got %s)" % score_rect.position.y)

	var rects: Dictionary = run._hud_zone_rects()
	var keys: Array = rects.keys()
	print("HUD_LAYOUT run %dx%d:" % [size.x, size.y])
	for key in keys:
		print("  %-10s %s" % [key, rects[key]])
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			_require(not a.intersects(b, true),
				"run HUD zones overlap at %dx%d: %s %s vs %s %s" % [size.x, size.y, keys[i], a, keys[j], b])

	run.state.elapsed = SURVIVAL
	run._update_time_label()
	_require(run._tag_time_label.text == "1:24", "timer should format mm:ss (got %s)" % run._tag_time_label.text)

	# The goal popup owns the opening seconds only; a restart brings it back.
	run._goal_tween.custom_step(4.0)
	_require(not run._goal_popup.visible, "crew-goal popup should hide after its hold + fade")
	run.restart()
	_require(run._goal_popup.visible, "a restart should re-show the crew-goal popup")

	# NEW BEST: passing the persisted best turns the score GOLD and reveals the
	# ribbon; the next restart clears both.
	run._best_at_start = 5
	run.state.score = 6
	run._update_hud()
	_require(run._new_best, "passing the persisted best must set the new-best state")
	_require(run._best_ribbon.visible, "NEW BEST ribbon should be visible")
	_require(run.score_label.get_theme_color("font_color") == Color("ffd23f"),
		"new-best score must be GOLD (got %s)" % run.score_label.get_theme_color("font_color"))
	run.restart()
	_require(not run._best_ribbon.visible and not run._new_best, "restart must clear the NEW BEST state")
	_require(run.score_label.get_theme_color("font_color") == Color("fff4dc"),
		"restart must restore the CREAM score")

	# Camera contract (owner decision 2026-10-01): the world zoom keeps the mascot
	# line where it sat at zoom 1.0 (the old ground-bottom pin made mascots read
	# shifted down) and the cap's x pinned, reveals more world ahead, and never
	# moves the HUD. The ceiling tracks the visible top; the ground stays on
	# screen inside the cloud sea.
	var zoom_root: Node2D = run._zoom_root
	_require(zoom_root != null, "world zoom root missing")
	var z: float = zoom_root.scale.x
	_require(z < 0.9 and z > 0.8, "world zoom should be ~0.88 (got %s)" % z)
	var cap_screen: Vector2 = zoom_root.position + run.cap.position * z
	_require(absf(cap_screen.x - run.tuning.cap_x) < 0.5, "cap x must stay pinned after zoom")
	var line_screen: float = zoom_root.position.y + run.tuning.mascot_line_y * z
	_require(absf(line_screen - run.tuning.mascot_line_y) < 0.5,
		"mascot line must sit where it did at zoom 1.0 (got %s)" % line_screen)
	var top_screen: float = zoom_root.position.y + run._view_top_y() * z
	_require(absf(top_screen) < 0.5, "ceiling must track the visible top (got %s)" % top_screen)
	var ground_screen: float = zoom_root.position.y + run._ground_y * z
	_require(ground_screen > 0.0 and ground_screen < float(size.y) - 1.0,
		"ground must stay visible above the viewport bottom (got %s)" % ground_screen)
	var right_edge := (float(size.x) - zoom_root.position.x) / z
	_require(right_edge > float(size.x) + 1.0, "zoom must reveal more world ahead (lookahead)")
	_require(run.ui_layer is CanvasLayer, "HUD must stay on a screen-space CanvasLayer")

	run.queue_free()
	save.queue_free()
	await process_frame

## Owner rule (2026-10-01): at most one text popup per event, and no two live
## popup rects may ever overlap. Exercises a perfect landing, a combo milestone,
## and a skip on top of an existing landing popup.
func _check_popup_rules(run: Node) -> void:
	run.restart()
	run.set_process(false)
	run.effects.clear()
	run.effects._process(0.016)

	var perfect_target := _first_unclaimed_target(run)
	_require(perfect_target != null, "no target for the perfect-landing popup check")
	run.cap.velocity_y = 320.0
	run.cap.position = Vector2(perfect_target.head_center_x(), perfect_target.head_top_y() - 5.0)
	run._resolve_landings()
	_require(run.effects._popups.size() == 1,
		"a perfect landing must spawn exactly one popup (got %d)" % run.effects._popups.size())
	_require(str(run.effects._popups[0]["text"]).begins_with("PERFECT +"),
		"the perfect popup should be one PERFECT +N label (got %s)" % run.effects._popups[0]["text"])
	_require_no_popup_overlap(run.effects, "perfect landing")

	# A combo milestone landing replaces the old popup and still spawns only one.
	run.effects.clear()
	run.state.combo = 4
	run._spawn._spawn_mascot(perfect_target.position.x + 700.0, true)
	var combo_target: MascotActor = run._spawn.mascots.back()
	_require(combo_target != null and is_instance_valid(combo_target), "no target for the combo popup check")
	run.cap.velocity_y = 320.0
	run.cap.position = Vector2(
		combo_target.head_center_x() + combo_target.head_half_width() * 0.8,
		combo_target.head_top_y() - 5.0
	)
	run._resolve_landings()
	_require(run.effects._popups.size() == 1,
		"a combo milestone must spawn exactly one popup (got %d)" % run.effects._popups.size())
	_require(str(run.effects._popups[0]["text"]).begins_with("×") and
		str(run.effects._popups[0]["text"]).ends_with("COMBO"),
		"a combo milestone should show the ×N COMBO sticker (got %s)" % run.effects._popups[0]["text"])
	_require_no_popup_overlap(run.effects, "combo milestone")

	# The -1 skip popup must never stack on a live landing popup.
	run.effects.clear()
	run.effects.popup(run.cap.position, "LANDING", Color.WHITE, 28)
	run.effects.popup(run.cap.position + Vector2(6.0, 0.0), "-1", Color("ff8a7a"), 30)
	_require(run.effects._popups.size() == 1,
		"the -1 popup must replace an overlapping popup (got %d)" % run.effects._popups.size())
	_require_no_popup_overlap(run.effects, "skip on landing popup")

	# Two popups at genuinely separate spots may coexist, still never overlapping.
	run.effects.clear()
	run.effects.popup(Vector2(200.0, 800.0), "ONE", Color.WHITE, 28)
	run.effects.popup(Vector2(480.0, 618.0), "TWO", Color.WHITE, 28)
	_require(run.effects._popups.size() == 2,
		"separate popups should coexist (got %d)" % run.effects._popups.size())
	_require_no_popup_overlap(run.effects, "separate popups")

func _require_no_popup_overlap(effects: Effects, label: String) -> void:
	var rects := effects.popup_rects()
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			_require(not rects[i].intersects(rects[j], true),
				"%s: popup rects overlap: %s vs %s" % [label, rects[i], rects[j]])

func _first_unclaimed_target(run: Node) -> MascotActor:
	for mascot in run._spawn.mascots:
		if is_instance_valid(mascot) and mascot.is_target and not mascot.claimed:
			return mascot
	return null

func _check_result_screen(size: Vector2i) -> void:
	for with_survival in [false, true]:
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await process_frame
		var flow := main.get_node("AppFlow") as AppFlow
		flow.transitions_enabled = false
		var payload := {
			"score": 42,
			"best": 42,
			"new_best": true,
			"reason": "FELL",
			"community_id": "mert",
			"community_name": "Mert",
			"contribution": 42,
			"streak": 1,
			"streak_multiplier": 1.0,
		}
		if with_survival:
			payload["survival_seconds"] = SURVIVAL
		flow.go_to(&"result", payload)
		await process_frame
		await process_frame
		var screen := flow.current_screen()
		_require(screen != null and screen.name == "ResultScreen", "result screen did not load")

		var retry: Button = screen._retry_button
		_require(retry != null and is_instance_valid(retry), "PLAY AGAIN missing")
		var survived := _find_survived(screen)
		if with_survival:
			_require(survived != null, "Survived line missing")
			_require(survived.text == "Survived 1:24", "unexpected survival line: %s" % survived.text)
			var label_rect: Rect2 = survived.get_global_rect()
			print("HUD_LAYOUT result %dx%d survived=%s retry=%s" % [
				size.x, size.y, label_rect, retry.get_global_rect(),
			])
			_require(not label_rect.intersects(retry.get_global_rect(), true),
				"Survived line overlaps PLAY AGAIN at %dx%d" % [size.x, size.y])
			_require(screen._page.get_combined_minimum_size().y <= screen._content_height + 1.0,
				"result page overflows its viewport at %dx%d" % [size.x, size.y])
		else:
			_require(survived == null, "survival line should not render without survival_seconds")

		_retry_positions[str(size) + ("+survival" if with_survival else "")] = retry.get_global_rect().position.y

		main.queue_free()
		await process_frame

	# PLAY AGAIN must not move when the survival line is added. The expanding gap
	# absorbs the extra line; Godot's integer layout rounding leaves a 1-3 px
	# wobble (this failed at 1.1 px on the base commit too), so allow a small
	# tolerance well under the ~35 px line height a real regression would add.
	var key := str(size)
	var plain: float = _retry_positions.get(key, 0.0)
	var with_line: float = _retry_positions.get(key + "+survival", 0.0)
	print("HUD_LAYOUT result %dx%d PLAY AGAIN y: without=%.1f with=%.1f" % [size.x, size.y, plain, with_line])
	_require(plain > 0.0 and absf(plain - with_line) <= 4.0,
		"PLAY AGAIN moved by %.1f px at %dx%d when the survival line was added" % [
			absf(plain - with_line), size.x, size.y,
		])

func _find_survived(node: Node) -> Label:
	for child in node.find_children("*", "Label", true, false):
		if (child as Label).text.begins_with("Survived"):
			return child as Label
	return null
