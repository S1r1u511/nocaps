extends SceneTree

## Phase 1 quests smoke test (docs/15 §4, §6): deterministic daily rotation,
## run-payload progress, one claim per quest per day, the 300-point daily cap,
## and UTC day rollover/reset.
##   scripts/run_tests.sh quests_smoke

const TestEnv := preload("res://tests/test_env.gd")

const DAY_A := 20000
const DAY_B := 20001
const DAY_C := 20002
const DAY_D := 20003


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if not TestEnv.begin("quests_smoke"):
		return
	_test_rotation()
	_test_progress_and_claim()
	_test_daily_cap()
	_test_rollover()
	_test_rivalry()
	print("QUESTS_PASS: rotation, progress, claims, cap, rollover verified")
	quit()


func _test_rotation() -> void:
	var first := Quests.daily_selection(DAY_A)
	var second := Quests.daily_selection(DAY_A)
	assert(first.size() == 3, "three daily quests are selected")
	assert(_ids(first) == _ids(second), "same UTC day yields the same rotation")

	var seen: Dictionary = {}
	var pool_ids := _pool_ids()
	for quest in first:
		var id := String(quest.get("id", ""))
		assert(not seen.has(id), "daily quests are unique")
		assert(pool_ids.has(id), "selection comes from the pool")
		seen[id] = true


func _test_progress_and_claim() -> void:
	var save := _make_save("progress")
	save.selected_community_id = &"mert"
	Quests.ensure_day(save, DAY_A)

	var chain := Quests.instance()
	var completed_ids: Array = []
	var changed := {"count": 0}
	var on_completed := func(quest: Dictionary) -> void:
		completed_ids.append(String(quest.get("id", "")))
	var on_changed := func() -> void:
		changed["count"] = int(changed["count"]) + 1
	chain.quest_completed.connect(on_completed)
	chain.quests_changed.connect(on_changed)

	var payload := {
		"community_id": "mert",
		"perfects": 999,
		"max_combo": 99,
		"landings": 999,
		"score": 99999,
		"contribution": 9999,
	}
	for i in range(3):
		Quests.record_run(save, payload, DAY_A)

	var daily := Quests.daily_quests(save, DAY_A)
	assert(daily.size() == 3, "three daily quests tracked")
	for quest in daily:
		assert(bool(quest.get("completed", false)), "quest completed: %s" % quest.get("id", ""))
	assert(completed_ids.size() == 3, "quest_completed fired once per daily quest")
	assert(int(changed["count"]) > 0, "quests_changed fired")

	var target := String(daily[0]["id"])
	var reward := int(daily[0]["reward"])
	assert(String(daily[0].get("state", "")) == "complete", "completed quest state is complete")
	var first: Dictionary = Quests.claim(save, target, null, DAY_A)
	assert(bool(first.get("ok", false)), "first claim succeeds")
	assert(int(save.quest_points_today) == reward, "claimed points recorded for the day")
	assert(save.day_total(&"mert") == reward, "quest points count as crew contribution")
	assert(save.pending_quest_claims.size() == 1, "claim queued for the backend")
	assert(String(Quests.daily_quests(save, DAY_A)[0].get("state", "")) == "claimed", "claimed quest state is claimed")

	var again: Dictionary = Quests.claim(save, target, null, DAY_A)
	assert(not bool(again.get("ok", true)), "second claim is rejected")
	assert(String(again.get("error", "")) == "already_claimed", "rejection reason is already_claimed")

	var unknown: Dictionary = Quests.claim(save, "not_a_quest", null, DAY_A)
	assert(String(unknown.get("error", "")) == "unknown_quest", "unknown quest rejected")

	chain.quest_completed.disconnect(on_completed)
	chain.quests_changed.disconnect(on_changed)
	save.free()


func _test_daily_cap() -> void:
	var save := _make_save("cap")
	save.selected_community_id = &"mert"
	Quests.ensure_day(save, DAY_A)
	_complete_daily(save, DAY_A)

	var target := String(Quests.daily_quests(save, DAY_A)[0]["id"])
	save.quest_points_today = Quests.DAILY_POINT_CAP - 10
	var blocked: Dictionary = Quests.claim(save, target, null, DAY_A)
	assert(not bool(blocked.get("ok", true)), "claim over the daily cap is rejected")
	assert(String(blocked.get("error", "")) == "daily_cap", "rejection reason is daily_cap")

	save.quest_points_today = 0
	var allowed: Dictionary = Quests.claim(save, target, null, DAY_A)
	assert(bool(allowed.get("ok", false)), "claim under the cap succeeds")
	assert(Quests.remaining_cap(save) == Quests.DAILY_POINT_CAP - int(allowed.get("points", 0)), "remaining cap reported")
	save.free()


func _test_rollover() -> void:
	var save := _make_save("rollover")
	save.selected_community_id = &"mert"
	Quests.ensure_day(save, DAY_C)
	_complete_daily(save, DAY_C)
	var claimed: Dictionary = Quests.claim(save, String(Quests.daily_quests(save, DAY_C)[0]["id"]), null, DAY_C)
	assert(bool(claimed.get("ok", false)), "day-1 claim succeeds")
	assert(save.quest_points_today > 0 and not save.quest_claimed.is_empty(), "day-1 state recorded")

	Quests.ensure_day(save, DAY_D)
	assert(save.quest_day_utc == DAY_D, "quest day advanced")
	assert(save.quest_claimed.is_empty(), "claims reset on rollover")
	assert(int(save.quest_points_today) == 0, "points reset on rollover")
	assert(save.quest_progress.is_empty(), "progress reset on rollover")

	_complete_daily(save, DAY_D)
	for quest in Quests.daily_quests(save, DAY_D):
		assert(bool(quest.get("completed", false)), "new-day quest tracks progress after reset")
	save.free()


func _test_rivalry() -> void:
	var save := _make_save("rivalry")
	save.selected_community_id = &"mert"
	# Force a fresh seed with the crew directly above (bitsy) within reach.
	save.quest_day_utc = -1
	save.day_start_day_utc = DAY_A
	save.day_contribution.clear()
	save.day_best.clear()
	save.day_contribution["bitsy"] = 100
	Quests.ensure_day(save, DAY_A)

	var rivalry := Quests.rivalry_quest(save, DAY_A)
	assert(not rivalry.is_empty(), "rivalry appears when the crew is within reach")
	assert(String(rivalry.get("rival_id", "")) == "bitsy", "rival is the crew directly above")
	assert(int(rivalry.get("target", 0)) == 2, "rivalry target is two runs")

	var payload := {"community_id": "mert", "landings": 1, "score": 10}
	Quests.record_run(save, payload, DAY_A)
	assert(int(Quests.rivalry_quest(save, DAY_A).get("progress", 0)) == 1, "rivalry progresses per crew run")
	Quests.record_run(save, payload, DAY_A)
	assert(bool(Quests.rivalry_quest(save, DAY_A).get("completed", false)), "rivalry completes after two runs")
	var claimed: Dictionary = Quests.claim(save, "rivalry_overtake", null, DAY_A)
	assert(bool(claimed.get("ok", false)), "rivalry claim succeeds")

	var far := _make_save("rivalry_far")
	far.selected_community_id = &"mert"
	far.quest_day_utc = -1
	far.day_start_day_utc = DAY_B
	far.day_contribution.clear()
	far.day_best.clear()
	far.day_contribution["bitsy"] = 999999
	assert(Quests.rivalry_quest(far, DAY_B).is_empty(), "rivalry hidden when the crew is out of reach")

	save.free()
	far.free()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_save(tag: String) -> SaveManager:
	var path := "user://nocaps_quests_%s.json" % tag
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = path
	root.add_child(save)
	return save


func _complete_daily(save: SaveManager, utc_day: int) -> void:
	var payload := {
		"community_id": String(save.selected_community_id),
		"perfects": 999,
		"max_combo": 99,
		"landings": 999,
		"score": 99999,
	}
	for i in range(3):
		Quests.record_run(save, payload, utc_day)


func _ids(quests: Array) -> Array:
	var out: Array = []
	for quest in quests:
		out.append(String(quest.get("id", "")))
	return out


func _pool_ids() -> Dictionary:
	var out: Dictionary = {}
	for quest in Quests.POOL:
		out[String(quest.get("id", ""))] = true
	return out
