extends SceneTree

## Board on a cold start: last session's member counts and today's rows paint
## immediately (no fake 0 / CONNECTING), and preview reward claims persist.
##   scripts/run_tests.sh board_cache_smoke

const TestEnv := preload("res://tests/test_env.gd")

func _score(rows: Array, id: String) -> int:
	for row in rows:
		if String(row["id"]) == id:
			return int(row["score"])
	return -1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("board_cache_smoke"):
		return
	Standings.clear_cache()
	assert(not Standings.members_known(&"mert"), "nothing is known on a clean install")
	assert(Standings.members_count(&"mert") == 0, "unknown count reads 0 internally")
	assert(not Standings.has_rows(), "no rows on a clean install")

	# A fetched count is remembered across sessions.
	Standings._snapshot_set("members:mert", 12)
	Standings._snapshot = {}
	Standings._snapshot_loaded = false
	assert(Standings.members_known(&"mert"), "last session's count is known after relaunch")
	assert(Standings.members_count(&"mert") == 12, "relaunch shows the last count, not 0 (got %d)" % Standings.members_count(&"mert"))

	# Today's rows from the last session count as paintable rows.
	Standings._remote_rows = [{"id": "mert", "communityId": "mert", "score": 40}]
	Standings._remote_period_id = Standings._today_id()
	Standings._cache_loaded = true
	assert(Standings.has_rows(), "cached rows for today are paintable")
	Standings.clear_cache()
	assert(not Standings.members_known(&"mert"), "clear_cache forgets the snapshot too")

	# One source of truth: once the backend answered for today, the board shows its
	# number (what the web shows) plus this device's still-queued runs, never the
	# device's own running total. Before any answer, the local total is the fallback.
	var src := SaveManager.new()
	src.save_path = "user://board_source_test_save.json"
	root.add_child(src)
	src.day_contribution["mert"] = 500
	src.day_contribution["wif"] = 70
	Standings.clear_cache()
	Standings._cache_loaded = true
	Standings._last_fetch_at = Time.get_ticks_msec() / 1000.0 + 3600.0
	assert(_score(Standings.communities_today(src), "mert") == 500, "no backend answer yet: local total is the fallback")
	Standings._remote_rows = [{"communityId": "mert", "score": 40}]
	Standings._remote_period_id = Standings._today_id()
	assert(_score(Standings.communities_today(src), "mert") == 40, "backend answered: its number wins over the local 500")
	assert(_score(Standings.communities_today(src), "wif") == 0, "a crew missing from the backend rows is 0, not the local 70")
	src.pending_submissions.append({"record": {"community_id": "mert", "contribution": 12, "client_created_at": int(Time.get_unix_time_from_system())}})
	src.pending_submissions.append({"record": {"community_id": "mert", "contribution": 99, "client_created_at": 1000}})
	assert(_score(Standings.communities_today(src), "mert") == 52, "today's queued runs are added; old ones are not")
	Standings._remote_rows = []
	assert(_score(Standings.communities_today(src), "mert") == 12, "a reset board shows 0 + queued, not the stale local total")
	src.queue_free()
	Standings.clear_cache()

	# Preview reward claims survive a restart.
	var save := SaveManager.new()
	save.save_path = "user://board_cache_test_save.json"
	root.add_child(save)
	save.reward_claims["mert:1"] = 1700000000
	save.save_data()
	var again := SaveManager.new()
	again.save_path = save.save_path
	root.add_child(again)
	again.load_data()
	assert(again.reward_claims.has("mert:1"), "preview claims persist")
	save.queue_free()
	again.queue_free()
	await process_frame
	print("BOARD_CACHE_PASS: cold-start counts/rows paint, claims persist")
	quit()
