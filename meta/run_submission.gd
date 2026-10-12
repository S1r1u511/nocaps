extends RefCounted
class_name RunSubmission

## Builds run records, queues them locally, and drains the queue against the
## backend boundary. Gameplay never blocks on the network: failed submissions
## stay queued and retry with backoff. See docs/10_BACKEND.md §7–8.

const QUEUE_LIMIT := 500
const BATCH_PER_FLUSH := 5
const RETRY_BASE_SECONDS := 30.0
const RETRY_FACTOR := 2.0
const RETRY_MAX_SECONDS := 900.0

## Per-run cap (Oct 10): the highest real score so far is under 500. Must match
## backend/firestore.rules. Contribution may add the streak bonus (up to x1.25).
const MAX_SCORE := 1000
const MAX_CONTRIBUTION := 1250
const MAX_DURATION_MS := 30 * 60 * 1000

## Where a run's points went (offline rule C, Oct 10). Shown on the Result screen.
## counted: on today's boards. pending: saved on the phone, counts if it syncs
## today. personal_only: played on an earlier server day, kept as a personal score.
const STATUS_COUNTED := "counted"
const STATUS_PENDING := "pending"
const STATUS_PERSONAL_ONLY := "personal_only"

## Builds a run record per docs/10_BACKEND.md §4.3. `duration_seconds` is converted
## to milliseconds; the server timestamp is authoritative once submitted.
static func build_record(
	player_id: String,
	community_id: StringName,
	score: int,
	landings: int,
	contribution: int,
	duration_seconds: float,
	streak_days: int
) -> Dictionary:
	return {
		"run_id": _new_run_id(player_id),
		"player_id": player_id,
		"community_id": String(community_id),
		"score": score,
		"landings": landings,
		"contribution": contribution,
		"streak_days": streak_days,
		"duration_ms": int(round(maxf(duration_seconds, 0.0) * 1000.0)),
		"game_version": str(ProjectSettings.get_setting("application/config/version", "dev")),
		"platform": _platform(),
		"client_created_at": int(Time.get_unix_time_from_system()),
		"validation_state": "accepted",
		"reward_eligible": false,
	}

## Rule C: true when the run was played on the current SERVER day. The play time
## is the device time at the end of the run, converted with the current server
## offset. Old records without a timestamp are treated as today (the rules still
## refuse any write outside the current server day).
static func counts_today(record: Dictionary) -> bool:
	var played := float(record.get("client_created_at", 0))
	if played <= 0.0:
		return true
	return ServerClock.day_number(ServerClock.to_server(played)) == ServerClock.day_number()

## Board status of a queued (not yet confirmed) record.
static func queued_status(record: Dictionary) -> String:
	return STATUS_PENDING if counts_today(record) else STATUS_PERSONAL_ONLY

## Cheap client-side sanitation. The server re-validates everything. MAX_SCORE
## matches the Spark rules bound (backend/firestore.rules) so an out-of-range run
## fails fast instead of retrying forever.
static func is_plausible(record: Dictionary) -> bool:
	if String(record.get("run_id", "")).is_empty():
		return false
	if String(record.get("community_id", "")).is_empty():
		return false
	var score := int(record.get("score", -1))
	var landings := int(record.get("landings", -1))
	var contribution := int(record.get("contribution", -1))
	var duration_ms := int(record.get("duration_ms", -1))
	if score < 0 or score > MAX_SCORE:
		return false
	if landings < 0 or landings > score:
		return false
	if contribution < 0 or contribution > MAX_CONTRIBUTION:
		return false
	if duration_ms < 0 or duration_ms > MAX_DURATION_MS:
		return false
	return true

## Adds a record to the local queue. Duplicate run ids are ignored. The queue holds
## 500 runs (hours of offline play); if it is ever full, the oldest entry is
## dropped and counted in `SaveManager.dropped_runs`, never silently (Oct 10, E13).
static func enqueue(save: SaveManager, record: Dictionary) -> bool:
	if save == null or not is_plausible(record):
		return false
	var run_id := String(record.get("run_id", ""))
	for entry in save.pending_submissions:
		if String(entry.get("record", {}).get("run_id", "")) == run_id:
			return false
	while save.pending_submissions.size() >= QUEUE_LIMIT:
		save.pending_submissions.remove_at(0)
		save.dropped_runs += 1
	save.pending_submissions.append({
		"record": record,
		"attempts": 0,
		"next_attempt_at": 0.0,
		"last_error": "",
	})
	save.save_data()
	return true

## Tries to submit due entries. Returns `{attempted, submitted, pending, error}`.
## `now` is injectable for tests; -1 means "now".
static func flush(save: SaveManager, client: Object, now: float = -1.0) -> Dictionary:
	if save == null:
		return {"attempted": 0, "submitted": 0, "pending": 0, "error": "no_save"}
	var now_s := now if now >= 0.0 else Time.get_unix_time_from_system()
	var attempted := 0
	var submitted := 0
	var last_error := ""
	var kept: Array = []
	for entry in save.pending_submissions:
		var due := float(entry.get("next_attempt_at", 0.0)) <= now_s
		if attempted >= BATCH_PER_FLUSH or not due:
			kept.append(entry)
			continue
		attempted += 1
		var result: Dictionary = client.submit_run(entry.get("record", {})) if client != null \
			else {"ok": false, "error": "offline"}
		if bool(result.get("ok", false)):
			submitted += 1
			continue
		entry["attempts"] = int(entry.get("attempts", 0)) + 1
		last_error = String(result.get("error", "unknown"))
		entry["last_error"] = last_error
		var delay: float = minf(
			RETRY_BASE_SECONDS * pow(RETRY_FACTOR, float(entry["attempts"]) - 1.0),
			RETRY_MAX_SECONDS
		)
		entry["next_attempt_at"] = now_s + delay
		kept.append(entry)
	save.pending_submissions = kept
	if attempted > 0:
		save.save_data()
	return {"attempted": attempted, "submitted": submitted, "pending": kept.size(), "error": last_error}

## Async drain used by the app: submits due records through the backend boundary
## and clears them when the server confirms. `on_done` receives the same summary
## shape as `flush`. Keeps `flush` synchronous for offline/queue tests.
static func flush_async(save: SaveManager, client: Object, on_done: Callable = Callable()) -> void:
	if save == null or client == null or not client.has_method("submit_run_async"):
		if on_done.is_valid():
			on_done.call({
				"attempted": 0,
				"submitted": 0,
				"pending": save.pending_submissions.size() if save != null else 0,
				"error": "offline",
			})
		return
	var now_s := Time.get_unix_time_from_system()
	var batch: Array = []
	for entry in save.pending_submissions:
		if batch.size() >= BATCH_PER_FLUSH:
			break
		if float(entry.get("next_attempt_at", 0.0)) <= now_s:
			batch.append(entry)
	if batch.is_empty():
		if on_done.is_valid():
			on_done.call({"attempted": 0, "submitted": 0, "pending": save.pending_submissions.size(), "error": ""})
		return
	var state := {"remaining": batch.size(), "submitted": 0, "personal": 0, "error": ""}
	for entry in batch:
		var run_id := String(entry.get("record", {}).get("run_id", ""))
		client.submit_run_async(entry.get("record", {}), func(result: Dictionary) -> void:
			if bool(result.get("ok", false)):
				state["submitted"] = int(state["submitted"]) + 1
				if String(result.get("board_status", STATUS_COUNTED)) == STATUS_PERSONAL_ONLY:
					state["personal"] = int(state["personal"]) + 1
				_remove_queued(save, run_id)
			else:
				state["error"] = String(result.get("error", "unknown"))
				_backoff_queued(save, run_id, now_s, String(state["error"]))
			state["remaining"] = int(state["remaining"]) - 1
			if int(state["remaining"]) <= 0:
				save.save_data()
				if on_done.is_valid():
					on_done.call({
						"attempted": batch.size(),
						"submitted": int(state["submitted"]),
						"personal": int(state["personal"]),
						"pending": save.pending_submissions.size(),
						"error": String(state["error"]),
					}))

static func _remove_queued(save: SaveManager, run_id: String) -> void:
	for i in range(save.pending_submissions.size() - 1, -1, -1):
		if String(save.pending_submissions[i].get("record", {}).get("run_id", "")) == run_id:
			save.pending_submissions.remove_at(i)
			return

static func _backoff_queued(save: SaveManager, run_id: String, now_s: float, error: String) -> void:
	for entry in save.pending_submissions:
		if String(entry.get("record", {}).get("run_id", "")) == run_id:
			entry["attempts"] = int(entry.get("attempts", 0)) + 1
			entry["last_error"] = error
			var delay: float = minf(
				RETRY_BASE_SECONDS * pow(RETRY_FACTOR, float(entry["attempts"]) - 1.0),
				RETRY_MAX_SECONDS
			)
			entry["next_attempt_at"] = now_s + delay
			return

## Summary for the Result/Profile UI.
static func status(save: SaveManager) -> Dictionary:
	if save == null:
		return {"pending": 0, "oldest_age_seconds": 0, "last_error": "", "dropped": 0}
	var oldest := 0
	var last_error := ""
	var now_s := Time.get_unix_time_from_system()
	for entry in save.pending_submissions:
		var created := int(entry.get("record", {}).get("client_created_at", 0))
		if created > 0:
			oldest = maxi(oldest, int(now_s) - created)
		var error := String(entry.get("last_error", ""))
		if not error.is_empty():
			last_error = error
	return {"pending": save.pending_submissions.size(), "oldest_age_seconds": oldest, "last_error": last_error, "dropped": save.dropped_runs}

static func _new_run_id(player_id: String) -> String:
	var who := player_id if not player_id.is_empty() else "guest"
	return "%s-%d-%04d" % [who, int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]

static func _platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("web"):
		return "web"
	return OS.get_name().to_lower()
