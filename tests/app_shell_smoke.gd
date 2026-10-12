extends SceneTree

## Phase 2 app-shell smoke test: the portrait shell boots on Home and routes
## between every screen with no dead ends. Run with:
##   scripts/run_tests.sh app_shell_smoke

const TestEnv := preload("res://tests/test_env.gd")

const EXPECTED := {
	&"home": "HomeScreen",
	&"community_select": "CommunitySelectScreen",
	&"community_detail": "CommunityDetailScreen",
	&"community_editor": "CommunityEditorScreen",
	&"run": "Run",
	&"result": "ResultScreen",
	&"leaderboard": "LeaderboardScreen",
	&"profile": "ProfileScreen",
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("app_shell_smoke"):
		return
	assert(ProjectSettings.get_setting("display/window/size/viewport_width") == 720, "baseline must be portrait 720 wide")
	assert(ProjectSettings.get_setting("display/window/size/viewport_height") == 1280, "baseline must be portrait 1280 tall")
	assert(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "baseline must request portrait")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "main scene must be the app shell")

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	var flow := main.get_node("AppFlow") as AppFlow
	assert(flow != null, "AppFlow missing from the shell")
	flow.transitions_enabled = false
	assert(main.get_node_or_null("SaveManager") != null, "SaveManager missing from the shell")
	assert(main.get_node_or_null("BackendClient") != null, "BackendClient missing from the shell")
	assert(flow.current_screen() != null and flow.current_screen().name == "HomeScreen", "shell did not start on Home")

	for screen_name in EXPECTED:
		flow.go_to(screen_name, {})
		await process_frame
		var screen := flow.current_screen()
		assert(screen != null, "screen failed to load: %s" % screen_name)
		assert(screen.name == EXPECTED[screen_name], "unexpected screen for %s: %s" % [screen_name, screen.name])

	main.queue_free()
	await process_frame
	print("APP_SHELL_PASS: portrait shell routes between all screens")
	quit()
