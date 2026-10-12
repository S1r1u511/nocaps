extends SceneTree

## Phase 4.2 submission smoke test: record construction, plausibility, queue
## dedupe/cap, retry backoff, successful drain, and status reporting.
##   scripts/run_tests.sh submission_smoke

const TestEnv := preload("res://tests/test_env.gd")

class FakeClient:
	var ok: bool = false
	var calls: int = 0
	func submit_run(_record: Dictionary) -> Dictionary:
		calls += 1
		if ok:
			return {"ok": true}
		return {"ok": false, "error": "offline"}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not TestEnv.begin("submission_smoke"):
		return
	var path := "user://nocaps_submission_test.json"
	_cleanup(path)
	var save := SaveManager.new()
	save.name = "SaveManager"
	save.save_path = path
	root.add_child(save)
	assert(not save.ensure_player_id().is_empty(), "guest player id is generated")
	var player_id := save.player_id
	assert(save.ensure_player_id() == player_id, "player id is stable")

	var record := RunSubmission.build_record(player_id, &"mert", 120, 12, 132, 45.5, 3)
	assert(RunSubmission.is_plausible(record), "built record should be plausible")
	assert(record["community_id"] == "mert", "community recorded")
	assert(record["score"] == 120 and record["landings"] == 12, "run facts recorded")
	assert(record["contribution"] == 132, "contribution recorded")
	assert(record["streak_days"] == 3, "streak recorded")
	assert(record["duration_ms"] == 45500, "duration converted to ms")
	assert(record["platform"] in ["macos", "linux", "windows", "android", "ios", "web"], "platform recorded: %s" % record["platform"])
	assert(record["reward_eligible"] == false, "demo runs are not reward eligible")
	assert(not String(record["game_version"]).is_empty(), "game version recorded")

	var bad := record.duplicate()
	bad["score"] = -5
	assert(not RunSubmission.is_plausible(bad), "negative score rejected")
	bad = record.duplicate()
	bad["duration_ms"] = RunSubmission.MAX_DURATION_MS + 1
	assert(not RunSubmission.is_plausible(bad), "absurd duration rejected")
	bad = record.duplicate()
	bad["community_id"] = ""
	assert(not RunSubmission.is_plausible(bad), "empty community rejected")

	assert(RunSubmission.enqueue(save, record), "valid record enqueued")
	assert(save.pending_submissions.size() == 1, "queue holds the record")
	assert(not RunSubmission.enqueue(save, record), "duplicate run id ignored")
	assert(save.pending_submissions.size() == 1, "duplicate did not grow the queue")
	assert(not RunSubmission.enqueue(save, bad), "implausible record rejected")

	# Queue cap keeps the newest entries.
	for i in range(RunSubmission.QUEUE_LIMIT + 10):
		var extra := RunSubmission.build_record(player_id, &"wif", 10 + i, 1, 10 + i, 5.0, 1)
		extra["run_id"] = "cap-%d" % i
		RunSubmission.enqueue(save, extra)
	assert(save.pending_submissions.size() == RunSubmission.QUEUE_LIMIT, "queue is capped")

	# A failed submission stays queued and backs off before retrying.
	save.pending_submissions.clear()
	var single := RunSubmission.build_record(player_id, &"mert", 90, 9, 90, 30.0, 2)
	single["run_id"] = "backoff-1"
	assert(RunSubmission.enqueue(save, single), "single record enqueued")
	var failing := FakeClient.new()
	var now := Time.get_unix_time_from_system()
	var first_flush := RunSubmission.flush(save, failing, now)
	assert(first_flush["attempted"] == 1, "due record attempted")
	assert(first_flush["submitted"] == 0, "offline submission does not succeed")
	assert(first_flush["pending"] == 1, "record stays queued")
	var oldest: Dictionary = save.pending_submissions[0]
	assert(int(oldest["attempts"]) == 1, "attempt counted")
	assert(float(oldest["next_attempt_at"]) > now, "retry is scheduled in the future")
	assert(String(oldest["last_error"]) == "offline", "last error recorded")
	assert(RunSubmission.status(save)["pending"] == 1, "status reports the pending record")

	var second_flush := RunSubmission.flush(save, failing, now + 1.0)
	assert(second_flush["attempted"] == 0, "backoff prevents an immediate retry")
	assert(second_flush["pending"] == 1, "queue unchanged during backoff")

	# Once the backend accepts, the queue drains.
	var accepting := FakeClient.new()
	accepting.ok = true
	var drained := RunSubmission.flush(save, accepting, now + RunSubmission.RETRY_MAX_SECONDS + 1.0)
	assert(drained["submitted"] == 1, "accepted record is removed")
	assert(drained["pending"] == 0, "queue drains")
	assert(RunSubmission.status(save)["pending"] == 0, "status reflects the drain")

	save.free()
	_cleanup(path)
	print("SUBMISSION_PASS: records, queue, backoff, drain verified")
	quit()

func _cleanup(path: String) -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
