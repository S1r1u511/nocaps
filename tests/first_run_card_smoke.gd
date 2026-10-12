extends SceneTree

## First-run result card: one dismissible card, no auto-focused name field (no
## keyboard over the score), and it never comes back once saved or dismissed.
## The wallet button is Android+bridge only, so it is absent on desktop.
##   scripts/run_tests.sh first_run_card_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("first_run_card_smoke"):
		return
	root.size = Vector2i(720, 1560)

	var save := SaveManager.new()
	save.name = "SaveManager"
	root.add_child(save)
	save.save_path = "user://first_run_card_test_save.json"
	save.runs_played = 1
	save.display_name = ""
	save.name_prompt_dismissed = false

	# The card shows once, on the page, with no keyboard.
	var screen := await _result(save)
	var card := screen.find_child("ResultOnboardCard", true, false) as Control
	assert(card != null, "the one-time card should show after the first run")
	assert(screen.find_child("ResultNamePrompt", true, false) == null,
		"the old overlay must be gone")
	var input := screen.find_child("ResultNameInput", true, false) as LineEdit
	assert(input != null, "the card needs a name field")
	assert(not input.has_focus(), "the name field must not auto-focus")
	assert(screen.find_child("ResultConnectWallet", true, false) == null,
		"the wallet button is Android+bridge only")
	input.text = "Cap King"
	screen._save_name()
	assert(save.display_name == "Cap_King", "saving sets the cleaned name")
	assert(card.is_queued_for_deletion(), "the card closes after saving")
	await process_frame
	screen.queue_free()

	# Named players are never asked again.
	screen = await _result(save)
	assert(screen.find_child("ResultOnboardCard", true, false) == null,
		"named players are not asked again")
	screen.queue_free()

	# Dismissal is remembered too.
	save.display_name = ""
	save.name_prompt_dismissed = false
	screen = await _result(save)
	var card2 := screen.find_child("ResultOnboardCard", true, false) as Control
	assert(card2 != null, "a fresh guest still sees the card")
	screen._skip_name()
	assert(save.name_prompt_dismissed, "Not now is remembered")
	assert(card2.is_queued_for_deletion(), "the card closes on dismiss")
	await process_frame
	screen.queue_free()
	screen = await _result(save)
	assert(screen.find_child("ResultOnboardCard", true, false) == null,
		"dismissed players are not asked again")
	screen.queue_free()

	save.queue_free()
	await process_frame
	print("FIRST_RUN_CARD_PASS: one card, no keyboard, never returns")
	quit()

func _result(save: SaveManager) -> Node:
	root.size = Vector2i(720, 1560)
	var screen: Node = load("res://scenes/ui/result_screen.tscn").instantiate()
	root.add_child(screen)
	screen.bind_services(save, null)
	screen.setup({"score": 12, "best": 20, "community_id": &"mert", "community_name": "Mert", "coins": 3})
	await process_frame
	return screen
