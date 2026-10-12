extends SceneTree

## ServerClock + offline rule C + local save/queue smoke test (Oct 10, A1-A2,
## C1-C2, E13).
##   scripts/run_tests.sh server_clock_smoke
##
## Covers: server-time parsing (RFC 3339 vs HTTP Date agree), counts_today /
## queued_status against a known server day, the 1000-point plausibility cap,
## save recovery from `.bak`, the 500-record queue drop counter, and version
## comparison.

const TestEnv := preload("res://tests/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("server_clock_smoke"):
		return

	# 1. The Firestore body timestamp and the HTTP Date header agree.
	var rfc := ServerClock.parse_rfc3339("2026-10-10T10:47:12.123Z")
	var http := ServerClock.parse_http_date("Sat, 10 Oct 2026 10:47:12 GMT")
	assert(rfc > 0.0, "RFC 3339 parsed")
	assert(is_equal_approx(rfc, http), "rfc3339 and http date agree (%f vs %f)" % [rfc, http])

	# 2. Offline rule C: same server day counts, the previous day is personal only.
	var device_now := Time.get_unix_time_from_system()
	ServerClock.set_server_time(device_now - 4321.0)
	var same_day := RunSubmission.build_record("p", &"mert", 100, 10, 100, 10.0, 1)
	same_day["client_created_at"] = int(device_now)
	assert(RunSubmission.counts_today(same_day), "a run played today counts")
	assert(RunSubmission.queued_status(same_day) == RunSubmission.STATUS_PENDING, "today's queued run is pending")
	var yesterday := RunSubmission.build_record("p", &"mert", 100, 10, 100, 10.0, 1)
	yesterday["client_created_at"] = int(device_now - ServerClock.SECONDS_PER_DAY)
	assert(not RunSubmission.counts_today(yesterday), "a run played yesterday does not count today")
	assert(RunSubmission.queued_status(yesterday) == "personal_only", "yesterday's run is personal only")
	ServerClock.reset()
	assert(not ServerClock.is_known(), "reset clears the known flag")

	# 3. Per-run cap: 1000 is plausible, 1001 is not.
	var capped := RunSubmission.build_record("p", &"mert", 1000, 10, 1000, 10.0, 1)
	assert(RunSubmission.is_plausible(capped), "score 1000 is plausible")
	capped["score"] = 1001
	assert(not RunSubmission.is_plausible(capped), "score 1001 is not plausible")

	# 4. Safe save: a corrupt main file is recovered from `.bak`.
	var path := "user://server_clock_test_save.json"
	_cleanup(path)
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = path
	root.add_child(save)
	save.best_score = 777
	save.save_data()
	save.save_data()
	assert(FileAccess.file_exists(path + ".bak"), "a backup is kept after a second save")
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{ this is not valid json")
	broken.close()
	save.best_score = 0
	save.load_data()
	assert(save.best_score == 777, "load_data restores from .bak (got %d)" % save.best_score)
	save.queue_free()

	# 5. Queue cap: the 501st enqueue drops the oldest and counts the drop.
	var qpath := "user://server_clock_queue_test.json"
	_cleanup(qpath)
	var qsave := SaveManager.new()
	qsave.name = "SaveManager"
	qsave.save_path = qpath
	root.add_child(qsave)
	for i in range(RunSubmission.QUEUE_LIMIT):
		var rec := RunSubmission.build_record("p", &"mert", 10, 1, 10, 5.0, 1)
		rec["run_id"] = "q-%d" % i
		assert(RunSubmission.enqueue(qsave, rec), "enqueue %d" % i)
	assert(qsave.pending_submissions.size() == RunSubmission.QUEUE_LIMIT, "queue is full at the limit")
	var overflow := RunSubmission.build_record("p", &"mert", 10, 1, 10, 5.0, 1)
	overflow["run_id"] = "q-over"
	assert(RunSubmission.enqueue(qsave, overflow), "overflow enqueue succeeds")
	assert(qsave.pending_submissions.size() == RunSubmission.QUEUE_LIMIT, "queue stays capped")
	assert(qsave.dropped_runs == 1, "one run dropped (got %d)" % qsave.dropped_runs)
	assert(String(qsave.pending_submissions[0].get("record", {}).get("run_id", "")) == "q-1", "the oldest record was dropped")
	qsave.queue_free()

	# 6. Version comparison.
	assert(AppVersion.compare("1.0.0", "1.0.1") == -1, "1.0.0 < 1.0.1")
	assert(AppVersion.compare("1.2.0", "1.10.0") == -1, "1.2.0 < 1.10.0 (numeric, not lexical)")
	assert(not AppVersion.is_below(""), "an empty minimum never blocks")

	_cleanup(path)
	_cleanup(qpath)
	print("SERVER_CLOCK_PASS: parsing, rule C, cap, save recovery, queue drop, versions verified")
	quit()

func _cleanup(path: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for suffix in ["", ".bak", ".tmp"]:
		var name: String = path.get_file() + suffix
		if dir.file_exists(name):
			dir.remove(name)
