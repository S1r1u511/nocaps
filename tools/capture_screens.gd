extends SceneTree

## Repeatable menu-screen capture for the screens-polish pass. Runs with a real
## renderer (not --headless) at 720x1560 and writes PNGs under
## `.build/reports/screens-polish/`:
##
##   Godot --path . --script res://tools/capture_screens.gd -- \
##     --suffix=before [--only=home,result]
##
## Each job boots `scenes/main.tscn` with a seeded save (or a clean one for the
## new-user state), navigates AppFlow to the screen, snaps animations, and grabs
## the viewport. Presentation-only: no gameplay rule is touched.

const OUT_DIR := "res://.build/reports/screens-polish"
const CAPTURE_SIZE := Vector2i(720, 1560)
const SCREEN_PAYLOADS := {
	&"home": {},
	&"community_select": {},
	&"community_detail": {},
	&"leaderboard": {},
	&"quests": {},
	&"profile": {},
	&"result": {},
}

var _suffix := "before"
var _only: PackedStringArray = PackedStringArray()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var options := _parse_args()
	_suffix = String(options.get("suffix", "before"))
	for name in String(options.get("only", "")).split(",", false):
		_only.append(name.strip_edges())
	var abs_out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_out)
	root.size = CAPTURE_SIZE
	await process_frame

	for job in _jobs():
		if not _only.is_empty() and not _only.has(String(job["name"])):
			continue
		await _capture(job, abs_out)
	quit()

# ---------------------------------------------------------------------------
# Jobs
# ---------------------------------------------------------------------------

func _jobs() -> Array:
	return [
		{ "name": "home_new", "save": {}, "screen": &"home", "payload": {} },
		{ "name": "home_rep", "save": _seed_save(&"mert"), "screen": &"home", "payload": {} },
		{ "name": "home_switch", "save": _seed_save(&"wif"), "screen": &"home", "payload": {},
			"focus": &"mert" },
		{ "name": "result", "save": _seed_save(&"mert"), "screen": &"result",
			"payload": {
				"score": 1240, "best": 1240, "new_best": true, "reason": "BUMPED!",
				"community_id": "mert", "community_name": "Mert", "contribution": 1240,
				"streak": 3, "streak_multiplier": 1.1, "survival_seconds": 84.0, "coins": 12,
			} },
		{ "name": "result_no_best", "save": _seed_save(&"wif"), "screen": &"result",
			"payload": {
				"score": 310, "best": 990, "new_best": false, "reason": "FELL",
				"community_id": "wif", "community_name": "Wif", "contribution": 341,
				"streak": 1, "streak_multiplier": 1.0, "survival_seconds": 41.0, "coins": 0,
			} },
		{ "name": "crew", "save": _seed_save(&"mert"), "screen": &"community_detail",
			"payload": {"community_id": "mert"} },
		{ "name": "crew_other", "save": _seed_save(&"mert"), "screen": &"community_detail",
			"payload": {"community_id": "mole"} },
		{ "name": "board", "save": _seed_save(&"wif"), "screen": &"leaderboard", "payload": {} },
		{ "name": "quests", "save": _seed_quests(&"mert"), "screen": &"quests", "payload": {} },
		{ "name": "explore", "save": _seed_save(&"mert"), "screen": &"community_select", "payload": {} },
		{ "name": "profile_guest", "save": _seed_save(&"mert"), "screen": &"profile", "payload": {} },
		{ "name": "profile_wallet", "save": _seed_save(&"mert"), "screen": &"profile", "payload": {},
			"connect_wallet": true },
		{ "name": "toast", "save": _seed_save(&"mert"), "screen": &"home", "payload": {},
			"toast": "You're now repping Mert" },
	]

# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

func _capture(job: Dictionary, abs_out: String) -> void:
	var save_data: Dictionary = job.get("save", {})
	_write_save(save_data)
	# A clean temp save means Standings must not paint stale rows from disk.
	Standings.clear_cache()
	Standings.clear_crew_cache()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	Moments.set_enabled(false)

	var screen: StringName = job["screen"]
	flow.go_to(screen, job.get("payload", {}))
	await process_frame
	await process_frame

	var current := flow.current_screen()
	if job.has("focus") and current != null and current.has_method("set_focus"):
		current.call("set_focus", StringName(job["focus"]))
		await process_frame

	if bool(job.get("connect_wallet", false)):
		var wallet := root.get_node_or_null("/root/WalletService")
		if wallet != null:
			wallet.call("connect_wallet")
			await process_frame
			await process_frame

	# Let entrance fades, count-ups and layout passes settle before snapping.
	await create_timer(1.6).timeout
	if job.has("toast"):
		Toasts.show_message(String(job["toast"]))
		await create_timer(0.35).timeout
	_snap_animations(current)
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("capture %s: empty viewport image" % job["name"])
	else:
		var path := "%s/%s_%s.png" % [abs_out, job["name"], _suffix]
		var error := image.save_png(path)
		if error != OK:
			push_error("capture %s: save failed (%s)" % [job["name"], error_string(error)])
		else:
			print("CAPTURE_SAVED %s %s" % [path, image.get_size()])

	main.queue_free()
	await process_frame
	Standings.clear_cache()
	Standings.clear_crew_cache()
	await process_frame

## Kills looping tweens and forces entrance animations to their settled state so
## two captures of the same state are comparable.
func _snap_animations(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is Control:
			var control := child as Control
			control.modulate.a = maxf(control.modulate.a, 0.999)
			control.scale = Vector2.ONE
		_snap_animations(child)

# ---------------------------------------------------------------------------
# Save seeding
# ---------------------------------------------------------------------------

func _seed_save(selected: StringName) -> Dictionary:
	var data := {
		"schema_version": 2,
		"selected_community_id": String(selected),
		"best_score": 1240,
		"best_time": 84.0,
		"coins_total": 321,
		"display_name": "Guest 4821",
		"runs_played": 27,
		"games_played": 27,
		"streak_days": 3,
		"last_played_day_utc": _today(),
		"day_start_day_utc": _today(),
		"week_start_day_utc": _week_start(),
		"day_contribution": {"mert": 3200, "wif": 2500, "bitsy": 1800, "mole": 900},
		"week_contribution": {"mert": 9800, "wif": 7400, "bitsy": 5100, "mole": 2600},
		"contribution_by_community": {"mert": 18400, "wif": 15200, "bitsy": 9700, "mole": 5200},
		"best_by_community": {"mert": 1240, "wif": 990, "bitsy": 860, "mole": 610},
		"week_best": {"mert": 1240, "wif": 990, "bitsy": 860, "mole": 610},
		"day_best": {"mert": 1240, "wif": 990, "bitsy": 860, "mole": 610},
		"tiers_reached": {"mert": 2, "wif": 2, "bitsy": 1},
		"unlocked_caps": ["mert", "wif", "bitsy"],
		"rare_caps": [],
	}
	return data

func _seed_quests(selected: StringName) -> Dictionary:
	var data := _seed_save(selected)
	var day := _today()
	var picked := Quests.daily_selection(day)
	if picked.size() >= 1:
		data["quest_progress"] = {String(picked[0]["id"]): int(picked[0]["target"])}
	if picked.size() >= 2:
		data["quest_claimed"] = [String(picked[1]["id"])]
		data["quest_points_today"] = 80
	data["quest_day_utc"] = day
	return data

func _write_save(data: Dictionary) -> void:
	if data.is_empty():
		if FileAccess.file_exists(SaveManager.DEFAULT_SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.DEFAULT_SAVE_PATH))
		return
	var file := FileAccess.open(SaveManager.DEFAULT_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))

func _today() -> int:
	return int(floor(Time.get_unix_time_from_system() / 86400.0))

func _week_start() -> int:
	var today := _today()
	var weekday := int(Time.get_datetime_dict_from_unix_time(today * 86400).get("weekday", 0))
	return today - (weekday + 6) % 7

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if not text.begins_with("--"):
			continue
		var body := text.substr(2)
		var split := body.split("=", true, 1)
		if split.size() == 2:
			out[split[0]] = split[1]
		else:
			out[body] = true
	return out
