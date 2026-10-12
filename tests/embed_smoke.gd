extends SceneTree

## Platform embed smoke test (platform/embed_service.gd, nocaps-web docs/EMBED.md):
## with `?embed=1&crew=<id>` the shell boots straight into the run for that crew,
## a run end posts `nocaps-run-finished`, and screens the platform owns (home,
## board, …) post `nocaps-exit` instead of opening inside the game.
##   scripts/run_tests.sh embed_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("embed_smoke"):
		return
	var sound := root.get_node_or_null("SoundService")
	if sound != null:
		sound.is_sound_enabled = false
		sound.is_music_enabled = false

	# Query parsing.
	assert(EmbedService.has_flag("?embed=1&crew=mert", "embed"), "embed=1")
	assert(EmbedService.has_flag("crew=mert&embed=true", "embed"), "embed=true")
	assert(EmbedService.has_flag("?embed", "embed"), "bare embed")
	assert(not EmbedService.has_flag("?embed=0", "embed"), "embed=0 is off")
	assert(not EmbedService.has_flag("?crew=mert", "embed"), "no embed param")
	assert(not EmbedService.has_flag("?embedded=1", "embed"), "only the exact key")

	# Not embedded: the normal shell boots on Home and posts nothing.
	EmbedService.use_query("?crew=wif")
	assert(not EmbedService.is_embedded(), "plain deep link is not embed mode")
	var plain: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(plain)
	await process_frame
	var plain_flow := plain.get_node("AppFlow") as AppFlow
	assert(plain_flow.current_screen().name != "Run", "plain boot must not jump into a run")
	assert(EmbedService.posted.is_empty(), "nothing is posted outside embed mode")
	plain.queue_free()
	await process_frame

	# Embedded: straight into the run for the requested crew.
	EmbedService.use_query("?embed=1&crew=solcity&name=Cap%20King")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var flow := main.get_node("AppFlow") as AppFlow
	flow.transitions_enabled = false
	assert(flow.current_screen() != null and flow.current_screen().name == "Run", "embed must boot into the run")
	var save := main.get_node("SaveManager") as SaveManager
	assert(save.display_name == "Cap_King", "the platform's name becomes the board name (got %s)" % save.display_name)
	assert(save.selected_community_id == &"solcity", "the platform's crew must be selected (got %s)" % save.selected_community_id)

	# A finished run reports to the platform.
	flow.go_to(&"result", {"score": 42, "coins": 7, "community_id": &"solcity", "best": 50, "new_best": false})
	await process_frame
	assert(flow.current_screen().name == "ResultScreen", "result still shows inside the game")
	var finished := _last("nocaps-run-finished")
	assert(not finished.is_empty(), "run end must post nocaps-run-finished")
	assert(finished["score"] == 42 and finished["coins"] == 7 and finished["crew"] == "solcity", "run payload: %s" % finished)
	assert(String(finished.get("name", "")).begins_with("Guest") or PlayerName.is_valid(String(finished.get("name", ""))), "run payload carries the board name: %s" % finished)

	# Wallet links from the platform are validated before anything is written.
	EmbedService.receive({"type": "nocaps-link-wallet", "address": "nope"}, "https://play.nocaps.fun")
	assert(not _last("nocaps-wallet-failed").is_empty(), "a bad wallet link is refused back to the platform")

	# A live battle from the platform: runs inside the window also add to the board.
	var site := "https://play.nocaps.fun"
	EmbedService.receive({"type": "nocaps-battle", "board": "cap-clash-1_solcity", "crew": "solcity", "startsInMs": -10000, "endsInMs": 60000}, site)
	assert(EmbedService.battle_board_for("solcity") == "cap-clash-1_solcity", "a run of the battle crew counts for the board")
	assert(EmbedService.battle_board_for("mole") == "", "other crews never touch this board")
	var now := Time.get_ticks_msec()
	assert(EmbedService.battle_board_for("solcity", now + 59500) == "", "too close to the end: skip the board, keep the run")
	EmbedService.receive({"type": "nocaps-battle", "board": "", "crew": ""}, site)
	assert(EmbedService.battle_board_for("solcity") == "", "an empty board ends the battle")
	EmbedService.receive({"type": "nocaps-battle", "board": "x_solcity", "crew": "solcity", "startsInMs": -1000, "endsInMs": 60000}, "https://evil.example")
	assert(EmbedService.battle_board_for("solcity") == "", "only the platform can start a battle")
	EmbedService.receive({"type": "nocaps-battle", "board": "Bad Id!", "crew": "solcity", "startsInMs": -1000, "endsInMs": 60000}, site)
	assert(EmbedService.battle_board_for("solcity") == "", "board ids are validated")

	# The board write: crew total + this player's row, as server-side increments.
	var backend := main.get_node("BackendClient") as BackendClient
	var old_id: String = backend.player_id
	backend.player_id = "uidABC"
	var w := backend._board_write("cap-clash-1_solcity", "run-1", 12, "Cap_King")
	backend.player_id = old_id
	assert(String(w["update"]["name"]).ends_with("/documents/boards/cap-clash-1_solcity"), "board doc path: %s" % w["update"]["name"])
	assert(w["updateMask"]["fieldPaths"] == ["lastRunId", "players.`uidABC`.n"], "mask: %s" % [w["updateMask"]])
	assert(w["updateTransforms"][0]["fieldPath"] == "score" and w["updateTransforms"][0]["increment"]["integerValue"] == "12", "crew increment")
	assert(w["updateTransforms"][1]["fieldPath"] == "players.`uidABC`.s", "player increment")
	assert(w["update"]["fields"]["players"]["mapValue"]["fields"].has("uidABC"), "player row keyed by uid")
	assert(w["currentDocument"]["exists"] == true, "never creates a board on its own")

	# Platform-owned screens leave the game instead of opening.
	flow.go_to(&"leaderboard", {})
	await process_frame
	assert(flow.current_screen().name == "ResultScreen", "board must not open inside the game")
	assert(_last("nocaps-exit").get("to", "") == "board", "board exits to the platform board")
	flow.go_to(&"home", {})
	await process_frame
	assert(_last("nocaps-exit").get("to", "") == "home", "home exits to the platform home")

	# Play again stays in the game.
	flow.go_to(&"run", {})
	await process_frame
	assert(flow.current_screen().name == "Run", "play again restarts the run in place")

	main.queue_free()
	await process_frame
	EmbedService.use_query("")
	print("EMBED_PASS: embed boots into the run, reports runs, exits to the platform")
	quit()

func _last(type: String) -> Dictionary:
	for i in range(EmbedService.posted.size() - 1, -1, -1):
		if EmbedService.posted[i].get("type", "") == type:
			return EmbedService.posted[i]
	return {}
