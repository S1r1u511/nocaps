extends SceneTree

## Player names (core/player_name.gd): validation, the guest fallback used on
## boards, and the one-time result-screen name card.
##   scripts/run_tests.sh player_name_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("player_name_smoke"):
		return
	assert(PlayerName.sanitize("  Cap King  ") == "Cap_King", "spaces become _")
	assert(PlayerName.sanitize("dg!!@@") == "dg", "symbols are dropped")
	assert(PlayerName.sanitize("a__b___c") == "a_b_c", "underscores collapse")
	assert(PlayerName.sanitize("x".repeat(30)).length() == PlayerName.MAX_LENGTH, "names are capped")
	assert(PlayerName.is_valid("DG_caps"), "a normal name is valid")
	assert(not PlayerName.is_valid("ab"), "too short")
	assert(not PlayerName.is_valid("Guest_1234"), "Guest is reserved")
	assert(not PlayerName.is_valid("fuckcaps"), "blocked words")
	assert(not PlayerName.is_valid("has space"), "spaces must be sanitized first")
	assert(PlayerName.guest_name("p-12-3456789") == "Guest 6789", "guest name uses the id's last digits")

	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://player_name_test_save.json"
	save.display_name = ""
	save.name_prompt_dismissed = false
	assert(PlayerName.board_name(save).begins_with("Guest "), "no name -> Guest on boards")
	save.display_name = "DG_caps"
	assert(PlayerName.board_name(save) == "DG_caps", "a saved name shows on boards")
	save.display_name = ""

	# Before any run: no card.
	save.runs_played = 0
	var screen := await _result(save)
	assert(screen.find_child("ResultOnboardCard", true, false) == null, "no card before the first run")
	screen.queue_free()

	# After a run: one card on the result, the name field is not auto-focused,
	# and saving a valid name closes it.
	save.runs_played = 1
	screen = await _result(save)
	var card := screen.find_child("ResultOnboardCard", true, false) as Control
	assert(card != null, "the card should show after a run")
	var input := screen.find_child("ResultNameInput", true, false) as LineEdit
	assert(input != null, "card needs an input")
	assert(not input.has_focus(), "the name field must not auto-focus (no keyboard)")
	var r := input.get_global_rect()
	assert(r.position.y >= 0.0 and r.end.y <= 1560.0, "input must sit on screen")
	input.text = "a!b"
	screen._save_name()
	assert(save.display_name.is_empty(), "an invalid name is not saved")
	input.text = "Cap King"
	screen._save_name()
	assert(save.display_name == "Cap_King", "the cleaned name is saved (got %s)" % save.display_name)
	assert(card.is_queued_for_deletion(), "card closes after saving")
	await process_frame
	screen.queue_free()

	# Named players are not asked again; skipping also stops the card.
	screen = await _result(save)
	assert(screen.find_child("ResultOnboardCard", true, false) == null, "named players are not asked again")
	screen.queue_free()
	save.display_name = ""
	screen = await _result(save)
	screen._skip_name()
	assert(save.name_prompt_dismissed, "skip is remembered")
	screen.queue_free()
	screen = await _result(save)
	assert(screen.find_child("ResultOnboardCard", true, false) == null, "skipped players are not asked again")
	screen.queue_free()

	# Profile: edit opens a full-width row with the input and SAVE on screen, and
	# the keyboard's Done key saves too.
	save.display_name = "DG_caps"
	root.size = Vector2i(720, 1560)
	var profile: Node = load("res://scenes/ui/profile_screen.tscn").instantiate()
	root.add_child(profile)
	profile.bind_services(save, null)
	profile.setup({})
	await process_frame
	profile._toggle_edit()
	await process_frame
	await process_frame
	var pin := profile.find_child("ProfileNameInput", true, false) as LineEdit
	var psave := profile.find_child("ProfileNameSave", true, false) as Control
	assert(pin != null and psave != null, "edit shows an input and a SAVE button")
	var sr := psave.get_global_rect()
	assert(sr.size.x >= 120.0 and sr.position.x >= 0.0 and sr.end.x <= 720.0, "SAVE is fully on screen (%s)" % sr)
	assert(pin.get_global_rect().size.x >= 200.0, "the name input has room (%s)" % pin.get_global_rect())
	pin.text = "Mole Fan"
	pin.text_submitted.emit(pin.text)
	await process_frame
	assert(save.display_name == "Mole_Fan", "Done on the keyboard saves the name (got %s)" % save.display_name)
	profile.queue_free()

	save.queue_free()
	await process_frame
	print("PLAYER_NAME_PASS: names validate, guests fall back, the prompt asks once")
	quit()

func _result(save: SaveManager) -> Node:
	root.size = Vector2i(720, 1560)
	var screen: Node = load("res://scenes/ui/result_screen.tscn").instantiate()
	root.add_child(screen)
	screen.bind_services(save, null)
	screen.setup({"score": 12, "best": 20, "community_id": &"mert", "community_name": "Mert", "coins": 3})
	await process_frame
	return screen
