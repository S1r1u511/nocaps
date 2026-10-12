extends SceneTree

## Backend emulator smoke test (Phase 4.3a). Not part of the default offline
## suite: it requires the local Firebase emulators to be running.
##
##   npx firebase-tools emulators:start --only auth,functions,firestore,pubsub --project demo-nocaps
##   scripts/run_tests.sh --emulator
##
## Verifies the real client path end to end: anonymous sign-in, snake_case ->
## camelCase mapping, submitRun acceptance, and a live leaderboard read.

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("backend_emulator_smoke"):
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var client := main.get_node("BackendClient") as BackendClient
	assert(client != null, "BackendClient missing from the shell")
	client.configure_for_emulator()
	assert(client.is_available(), "emulator config must be available")

	var submit := {"done": false, "result": {}}
	var record := RunSubmission.build_record("emulator-smoke", &"wif", 12, 4, 12, 12.0, 1)
	client.submit_run_async(record, func(result: Dictionary) -> void:
		submit["done"] = true
		submit["result"] = result)
	await _wait_for(func() -> bool: return bool(submit["done"]), "submitRun response")
	var submit_result: Dictionary = submit["result"]
	assert(bool(submit_result.get("ok", false)),
		"submitRun should accept the mapped record: %s" % str(submit_result))

	var board := {"done": false, "result": {}}
	client.fetch_leaderboard_async(&"communities", &"weekly", func(result: Dictionary) -> void:
		board["done"] = true
		board["result"] = result)
	await _wait_for(func() -> bool: return bool(board["done"]), "getLeaderboard response")
	var rows_result: Dictionary = board["result"]
	assert(bool(rows_result.get("ok", false)),
		"getLeaderboard should return live rows: %s" % str(rows_result))
	assert(rows_result.get("rows", []) is Array, "leaderboard rows must be an array")

	main.queue_free()
	await process_frame
	print("BACKEND_EMULATOR_PASS: client signed in, submitted, and read the leaderboard")
	quit()

func _wait_for(predicate: Callable, label: String) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return
		await process_frame
	push_error("BACKEND_EMULATOR_FAIL: timed out waiting for %s (are the emulators running?)" % label)
	quit(1)
