extends RefCounted

## Test isolation guard for every smoke test.
##
## `scripts/run_tests.sh` launches each test with a fresh temporary
## HOME / XDG_DATA_HOME plus `NOCAPS_TEST_ROOT` pointing at that temp dir, so
## `user://` resolves inside an empty throwaway folder and can never read or
## write the real save, settings, caches, or DEV presets.
##
## Call `TestEnv.begin("<test_name>")` first thing in `run()`. It returns false
## (and quits with exit code 2) when the test is not isolated, so a bare
## `godot --headless --script res://tests/<name>.gd` run aborts instead of
## silently touching the real user data.

const ROOT_ENV := "NOCAPS_TEST_ROOT"
const REAL_SAVE := "user://nocaps_v1.json"


static func begin(test_name: String) -> bool:
	var root := OS.get_environment(ROOT_ENV)
	if root.is_empty():
		return _abort(test_name, "%s is not set; run scripts/run_tests.sh instead of invoking this test directly" % ROOT_ENV)
	var user_dir := OS.get_user_data_dir().simplify_path()
	var isolated_root := root.simplify_path()
	var prefix := isolated_root if isolated_root.ends_with("/") else isolated_root + "/"
	if user_dir != isolated_root and not user_dir.begins_with(prefix):
		return _abort(test_name, "user:// resolves to %s, outside the isolated test root %s" % [user_dir, isolated_root])
	if FileAccess.file_exists(REAL_SAVE):
		return _abort(test_name, "a real save is visible to the test at %s" % REAL_SAVE)
	return true


static func _abort(test_name: String, reason: String) -> bool:
	printerr("TEST_ENV_FAIL[%s]: %s" % [test_name, reason])
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).quit(2)
	return false
