extends SceneTree

## Phase 4.1 local progress smoke test: streak multiplier, contribution banking,
## weekly tiers, week rollover, reset, and v1→v2 save migration.
##   scripts/run_tests.sh progress_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("progress_smoke"):
		return
	_test_scoring_math()
	_test_banking()
	_test_migration()
	print("PROGRESS_PASS: streak, contribution, tiers, migration verified")
	quit()

func _test_scoring_math() -> void:
	assert(is_equal_approx(Scoring.streak_multiplier(1), 1.0), "day 1 = x1")
	assert(is_equal_approx(Scoring.streak_multiplier(2), 1.05), "day 2 = x1.05")
	assert(is_equal_approx(Scoring.streak_multiplier(6), 1.25), "day 6 = x1.25")
	assert(is_equal_approx(Scoring.streak_multiplier(50), 1.25), "cap holds")
	assert(Scoring.contribution_for(100, 6) == 125, "contribution applies the streak bonus")
	var tiers := PackedInt32Array([150, 450, 1100])
	assert(Scoring.tier_index(149, tiers) == 0, "below first tier")
	assert(Scoring.tier_index(150, tiers) == 1, "first tier")
	assert(Scoring.tier_index(600, tiers) == 2, "second tier")
	assert(Scoring.tier_index(5000, tiers) == 3, "all tiers")
	assert(Scoring.next_tier_total(150, tiers) == 450, "next tier")
	assert(Scoring.next_tier_total(5000, tiers) == -1, "no next tier")
	assert(is_equal_approx(Scoring.tier_progress(300, tiers), 0.5), "halfway to second tier")

func _test_banking() -> void:
	var path := "user://nocaps_progress_test.json"
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("nocaps_progress_test.json"):
		dir.remove("nocaps_progress_test.json")
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = path
	root.add_child(save)

	var tiers := PackedInt32Array([150, 450, 1100])
	var first := save.record_run(&"mert", tiers, 100, 10, 30.0, 100, 98)
	assert(first["streak"] == 1, "first run starts a streak")
	assert(first["contribution"] == 100, "no bonus day one")
	assert(first["week_total"] == 100, "week total accumulates")
	assert(not first["tier_crossed"], "no tier below the threshold")

	var second := save.record_run(&"mert", tiers, 100, 10, 30.0, 100, 98)
	assert(second["streak"] == 1, "same day does not advance the streak")
	assert(second["contribution"] == 100, "same-day bonus unchanged")
	assert(second["week_total"] == 200, "week total accumulates same day")
	assert(second["tier_crossed"] and second["tier_after"] == 1, "first tier crossed")

	var third := save.record_run(&"mert", tiers, 100, 10, 30.0, 101, 98)
	assert(third["streak"] == 2, "next day advances the streak")
	assert(third["contribution"] == 105, "streak bonus applies")
	assert(third["week_total"] == 305, "week total keeps accumulating")

	var other := save.record_run(&"wif", tiers, 200, 12, 40.0, 101, 98)
	assert(other["week_total"] == 210, "other community tracked separately")
	assert(save.total_contribution(&"mert") == 305, "mert total persists")
	assert(save.total_contribution(&"wif") == 210, "wif total persists")
	assert(save.best_for(&"wif") == 200, "per-community best")
	assert(save.best_time == 40.0, "longest survival time is saved")
	assert(save.day_total(&"mert") == 105, "daily total resets on a new day")
	assert(save.day_total(&"wif") == 210, "daily total tracked per community")
	assert(save.week_best_for(&"mert") == 100, "weekly best tracked")
	assert(save.day_best_for(&"wif") == 200, "daily best tracked")

	# A new week resets weekly totals and tiers but not all-time totals.
	var fresh_week := save.record_run(&"mert", tiers, 50, 5, 20.0, 110, 105)
	assert(fresh_week["week_total"] == 50, "weekly total resets")
	assert(not fresh_week["tier_crossed"], "weekly tiers reset")
	assert(fresh_week["streak"] == 1, "streak resets after a gap")
	assert(save.total_contribution(&"mert") == 355, "all-time total persists")
	assert(save.week_best_for(&"mert") == 50, "weekly best resets with the week")

	save.reset_all()
	assert(save.best_score == 0 and save.streak_days == 0, "reset clears progress")
	assert(save.best_time == 0.0, "reset clears the best survival time")
	assert(save.total_contribution(&"mert") == 0, "reset clears contributions")
	save.free()

func _test_migration() -> void:
	var path := "user://nocaps_migration_test.json"
	var legacy := {
		"schema_version": 1,
		"selected_community_id": "wif",
		"best_score": 42,
		"player_id": "legacy",
		"muted": true,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file = null

	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = path
	root.add_child(save)
	assert(save.best_score == 42, "legacy best preserved")
	assert(save.best_for(&"wif") == 42, "legacy best moved into per-community")
	assert(save.muted, "legacy settings preserved")
	var parsed: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	assert(int(parsed.get("schema_version", 0)) == 2, "save migrated to v2")
	save.free()
