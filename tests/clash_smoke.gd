extends SceneTree

## Today's Clash rule (meta/clash.gd): the shared fixture (ordering, ties, zero
## scores), the UTC reset, and that pending runs on this device are part of the
## rows the rule reads. The same fixture drives the web unit test.
##   scripts/run_tests.sh clash_smoke

const TestEnv := preload("res://tests/test_env.gd")
const FIXTURE_PATH := "res://tests/clash_fixture.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("clash_smoke"):
		return
	var fixture := _load_fixture()
	assert(not fixture.is_empty(), "fixture loads")

	for case in fixture.get("cases", []):
		_assert_case(case)

	var reset: Dictionary = fixture.get("reset", {})
	var now := int(reset.get("now", 0))
	assert(Clash.seconds_to_reset(now) == int(reset.get("seconds", -1)),
		"seconds to UTC reset (got %d)" % Clash.seconds_to_reset(now))
	assert(Clash.reset_text(now) == String(reset.get("text", "")),
		"reset text (got %s)" % Clash.reset_text(now))

	# Pending runs on this device are part of today's board, so they can flip the clash.
	Standings.clear_cache()
	Standings._cache_loaded = true
	Standings._last_fetch_at = Time.get_ticks_msec() / 1000.0 + 3600.0
	Standings._remote_rows = [
		{"communityId": "mert", "score": 60},
		{"communityId": "wif", "score": 100},
	]
	Standings._remote_period_id = Standings._today_id()
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = "user://clash_test_save.json"
	root.add_child(save)

	var before := Clash.today(save)
	assert(bool(before["active"]), "two crews with points make a clash")
	assert(String(before["a"]["id"]) == "wif" and String(before["b"]["id"]) == "mert",
		"clash before pending: %s" % [before])

	save.pending_submissions.append({
		"record": {
			"community_id": "mert",
			"contribution": 50,
			"client_created_at": int(Time.get_unix_time_from_system()),
		},
	})
	var after := Clash.today(save)
	assert(String(after["a"]["id"]) == "mert" and int(after["a"]["score"]) == 110,
		"pending runs push the crew up: %s" % [after])
	assert(Clash.has_crew(after, &"wif") and not Clash.has_crew(after, &"bitsy"),
		"has_crew sees only the two clash crews")

	save.free()
	Standings.clear_cache()
	print("CLASH_PASS: fixture, UTC reset, pending runs included")
	quit()

func _assert_case(case: Dictionary) -> void:
	var name := String(case.get("name", "?"))
	var got := Clash.from_rows(case.get("rows", []))
	var expected: Dictionary = case.get("expected", {})
	assert(bool(got["active"]) == bool(expected.get("active", false)), "%s: active" % name)
	if bool(expected.get("active", false)):
		_assert_side(name, "a", got.get("a"), expected.get("a"))
		_assert_side(name, "b", got.get("b"), expected.get("b"))
	else:
		assert(got.get("a") == null and got.get("b") == null, "%s: no sides when inactive" % name)

func _assert_side(case_name: String, key: String, got: Variant, expected: Variant) -> void:
	assert(got is Dictionary and expected is Dictionary, "%s: side %s is a row" % [case_name, key])
	var g: Dictionary = got
	var e: Dictionary = expected
	assert(String(g.get("id", "")) == String(e.get("id", "")),
		"%s: %s id (got %s)" % [case_name, key, g.get("id", "")])
	assert(String(g.get("name", "")) == String(e.get("name", "")),
		"%s: %s name (got %s)" % [case_name, key, g.get("name", "")])
	assert(int(g.get("score", -1)) == int(e.get("score", -2)),
		"%s: %s score (got %s)" % [case_name, key, g.get("score", "")])

func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
