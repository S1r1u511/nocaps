extends RefCounted
class_name Race

## Community race momentum + event layer, computed client-side from successive
## standings snapshots (docs/15_COMPETITION_AND_QUESTS.md §3).
##
## - snapshots every 10 s in a 10-minute ring buffer, persisted to
##   `user://race_history.json` so a relaunch keeps some context;
## - momentum "+N in the last M min" with M = the real buffer span (shown only
##   once the span reaches 2 minutes);
## - overtake/overtaken events retained for 30 minutes;
## - one pure helper per scoreboard trigger, so UI/gameplay code owns no math.
##
## Nothing here is authoritative: it is a client-side view over cached standings.
## A server-side event feed is LATER (Blaze).

const SNAPSHOT_SECONDS := 10.0
const WINDOW_SECONDS := 600.0
const EVENT_SECONDS := 1800.0
const MIN_SPAN_SECONDS := 120.0
const MOMENTUM_THRESHOLD := 200
const MAX_SURGING := 2
const MAX_RUNS := 20
const MAX_SNAPSHOTS := 90
const BASE_GAP_FLOOR := 150
const GAP_MEDIAN_FACTOR := 3
const CATCH_MULTIPLIER := 2

const DEFAULT_HISTORY_PATH := "user://race_history.json"

var history_path: String = DEFAULT_HISTORY_PATH
## [{t: float, rows: [{id, score}]}], oldest first.
var _snapshots: Array = []
## [{t: float, type: "overtake", by: String, over: String}], oldest first.
var _events: Array = []
## Recent banked run contributions, oldest first (for the median gap threshold).
var _runs: Array = []
var _last_snapshot_at: float = -1.0
var _loaded: bool = false

func _init(path: String = "") -> void:
	if not path.is_empty():
		history_path = path

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

## Records a standings snapshot (throttled to once per SNAPSHOT_SECONDS) and
## detects overtakes between the previous and current ranking.
func observe(rows: Array, now: float = -1.0) -> void:
	_load()
	var t := _now(now)
	if _last_snapshot_at >= 0.0 and t - _last_snapshot_at < SNAPSHOT_SECONDS:
		return
	_last_snapshot_at = t
	var previous: Array = _snapshots[-1]["rows"] if not _snapshots.is_empty() else []
	var current: Array = _rows_snapshot(rows)
	_snapshots.append({"t": t, "rows": current})
	_detect_overtakes(previous, current, t)
	_prune(t)
	_save()

## Remembers a banked run contribution for the median gap threshold.
func note_run(contribution: int, now: float = -1.0) -> void:
	_load()
	_runs.append({"t": _now(now), "contribution": maxi(contribution, 0)})
	while _runs.size() > MAX_RUNS:
		_runs.pop_front()
	_save()

func clear() -> void:
	_snapshots.clear()
	_events.clear()
	_runs.clear()
	_last_snapshot_at = -1.0
	_loaded = true
	if FileAccess.file_exists(history_path):
		DirAccess.remove_absolute(history_path)

# ---------------------------------------------------------------------------
# Momentum and events
# ---------------------------------------------------------------------------

## id -> {gain: int, span_seconds: int}; only crews present in both ends.
func momentum(now: float = -1.0) -> Dictionary:
	_load()
	var t := _now(now)
	_prune(t)
	var out: Dictionary = {}
	if _snapshots.size() < 2:
		return out
	var span := t - float(_snapshots[0]["t"])
	if span < MIN_SPAN_SECONDS:
		return out
	var first_rows: Array = _snapshots[0]["rows"]
	var last_rows: Array = _snapshots[-1]["rows"]
	var last_scores: Dictionary = {}
	for row in last_rows:
		last_scores[String(row["id"])] = int(row["score"])
	for row in first_rows:
		var id := String(row["id"])
		if not last_scores.has(id):
			continue
		out[id] = {
			"gain": int(last_scores[id]) - int(row["score"]),
			"span_seconds": int(span),
		}
	return out

## Top surging crews (gain >= MOMENTUM_THRESHOLD), highest gain first:
## [{id, gain, span_seconds}].
func momentum_line(now: float = -1.0) -> Array:
	var gains: Dictionary = momentum(now)
	var surging: Array = []
	for id in gains:
		if int(gains[id]["gain"]) >= MOMENTUM_THRESHOLD:
			surging.append({
				"id": id,
				"gain": int(gains[id]["gain"]),
				"span_seconds": int(gains[id]["span_seconds"]),
			})
	surging.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["gain"]) > int(b["gain"]))
	return surging.slice(0, MAX_SURGING)

## Rank change per crew since the oldest snapshot in the window: positive means
## the crew moved up. Empty when there is nothing to compare.
func rank_arrows(rows: Array, now: float = -1.0) -> Dictionary:
	_load()
	var t := _now(now)
	_prune(t)
	var out: Dictionary = {}
	if _snapshots.is_empty() or rows.is_empty():
		return out
	var before: Dictionary = _rank_by_id(_snapshots[0]["rows"])
	var after: Dictionary = _rank_by_id(rows)
	for id in after:
		if before.has(id):
			out[id] = int(before[id]) - int(after[id])
	return out

## Overtake events within the last 30 minutes; filter by crew when given.
func recent_events(now: float = -1.0, community_id: String = "") -> Array:
	_load()
	var t := _now(now)
	_prune(t)
	var out: Array = []
	for event in _events:
		if not community_id.is_empty() \
				and String(event.get("by", "")) != community_id \
				and String(event.get("over", "")) != community_id:
			continue
		out.append(event.duplicate())
	return out

# ---------------------------------------------------------------------------
# Per-trigger helpers (docs/15_COMPETITION_AND_QUESTS.md §3)
# ---------------------------------------------------------------------------

## The crew immediately above the player's crew, when the gap is within
## `max(150, 3 x median run contribution)`. {} when hidden.
func gap_to_pass(rows: Array, my_id: String, median_hint: int = -1) -> Dictionary:
	var index := _index_of(rows, my_id)
	if index <= 0:
		return {}
	var above: Dictionary = rows[index - 1]
	var mine: Dictionary = rows[index]
	var gap := int(above["score"]) - int(mine["score"])
	var median := median_hint if median_hint >= 0 else median_run_contribution()
	var threshold := maxi(BASE_GAP_FLOOR, GAP_MEDIAN_FACTOR * median)
	if gap > threshold:
		return {}
	return {
		"id": String(above["id"]),
		"name": String(above["name"]),
		"gap": gap,
		"threshold": threshold,
	}

## Would this run's contribution push the player's crew above the crew above?
func run_overtake(rows: Array, my_id: String, contribution: int, my_score: int = -1) -> Dictionary:
	var index := _index_of(rows, my_id)
	if index <= 0:
		return {}
	var above: Dictionary = rows[index - 1]
	var current := int(rows[index]["score"]) if my_score < 0 else my_score
	if current + contribution <= int(above["score"]):
		return {}
	return {"id": String(above["id"]), "name": String(above["name"])}

## Does this contribution pass the next player above in the crew list?
## `player_rows` is the crew's player ranking (highest first).
func crew_rank_up(player_rows: Array, my_uid: String, contribution: int, my_score: int = -1) -> Dictionary:
	var my_rank := 0
	var my_value := my_score
	for i in range(player_rows.size()):
		var row: Dictionary = player_rows[i]
		if String(row.get("uid", "")) == my_uid:
			my_rank = i + 1
			if my_value < 0:
				my_value = int(row["score"])
			break
	if my_rank <= 1 or my_value < 0:
		return {}
	var above: Dictionary = player_rows[my_rank - 2]
	if my_value + contribution <= int(above["score"]):
		return {}
	return {"uid": String(above.get("uid", "")), "name": String(above.get("name", "")), "rank": my_rank - 1}

## Result card data when the crew climbed during the run. {} when unchanged.
func rank_moved(rank_before: int, rank_after: int, community_name: String = "") -> Dictionary:
	if rank_before <= 0 or rank_after <= 0 or rank_after >= rank_before:
		return {}
	return {"from": rank_before, "to": rank_after, "name": community_name}

## "ONE MORE — CATCH {Crew}" when the crew above is reachable within two runs.
func catch_cta(rows: Array, my_id: String, contribution: int, median_hint: int = -1) -> Dictionary:
	var target := gap_to_pass(rows, my_id, median_hint)
	if target.is_empty():
		return {}
	var run_value := contribution if contribution > 0 else median_run_contribution()
	if run_value <= 0 or int(target["gap"]) > CATCH_MULTIPLIER * run_value:
		return {}
	target["text"] = "ONE MORE — CATCH %s" % String(target["name"]).to_upper()
	return target

## One live-ticker line: a rival closing in, or a recent overtake involving the
## player's crew. {} when nothing notable happened.
func live_ticker(rows: Array, my_id: String, now: float = -1.0) -> Dictionary:
	var index := _index_of(rows, my_id)
	var gains: Dictionary = momentum(now)
	if index > 0 and not gains.is_empty():
		var my_score := int(rows[index]["score"])
		var above: Dictionary = rows[index - 1]
		var above_gain: Variant = gains.get(String(above["id"]))
		if above_gain != null and int(above_gain["gain"]) >= MOMENTUM_THRESHOLD:
			var gap := int(above["score"]) - my_score
			if float(gap) <= maxf(float(my_score) * 0.1, 50.0):
				return {
					"type": "closing",
					"id": String(above["id"]),
					"name": String(above["name"]),
					"gain": int(above_gain["gain"]),
					"span_seconds": int(above_gain["span_seconds"]),
				}
	var events := recent_events(now, my_id)
	if not events.is_empty():
		var event: Dictionary = events[-1]
		return {
			"type": "overtake",
			"id": String(event.get("by", "")),
			"over": String(event.get("over", "")),
			"by": String(event.get("by", "")),
			"span_seconds": 0,
		}
	return {}

## Seconds until the current UTC day ends; `last_hour` drives the pulsing
## countdown treatment.
func day_ending(now: float = -1.0) -> Dictionary:
	var t := _now(now)
	var start := _utc_day_start(t)
	var seconds_left := int(maxf(0.0, start + 86400.0 - t))
	return {
		"seconds_left": seconds_left,
		"last_hour": seconds_left <= 3600,
		"clock": _clock(seconds_left),
	}

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _rows_snapshot(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		if not row is Dictionary:
			continue
		out.append({"id": String(row.get("id", "")), "score": int(row.get("score", 0))})
	return out

func _detect_overtakes(previous: Array, current: Array, t: float) -> void:
	if previous.is_empty() or current.is_empty():
		return
	var before: Dictionary = _rank_by_id(previous)
	var after: Dictionary = _rank_by_id(current)
	for id in after:
		if not before.has(id):
			continue
		var was: int = int(before[id])
		var is_now: int = int(after[id])
		if is_now >= was:
			continue
		# The crew directly below `id` now must have been above it before.
		for other in after:
			if String(other) == String(id):
				continue
			if int(after[other]) == is_now + 1 and int(before.get(other, 999)) < was:
				_events.append({"t": t, "type": "overtake", "by": String(id), "over": String(other)})
				break

## id -> rank (1-based) for a snapshot's rows (already ranked input or not).
func _rank_by_id(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	var sorted: Array = rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0)))
	for i in range(sorted.size()):
		out[String(sorted[i].get("id", ""))] = i + 1
	return out

func _index_of(rows: Array, id: String) -> int:
	for i in range(rows.size()):
		if rows[i] is Dictionary and String(rows[i].get("id", "")) == id:
			return i
	return -1

func _prune(t: float) -> void:
	while not _snapshots.is_empty() and t - float(_snapshots[0]["t"]) > WINDOW_SECONDS:
		_snapshots.pop_front()
	while _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()
	while not _events.is_empty() and t - float(_events[0]["t"]) > EVENT_SECONDS:
		_events.pop_front()

func _now(value: float) -> float:
	return value if value >= 0.0 else Time.get_unix_time_from_system()

func _clock(seconds: int) -> String:
	var hours := int(seconds / 3600.0)
	var minutes := int((seconds % 3600) / 60.0)
	var secs := seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%d:%02d" % [minutes, secs]

static func _utc_day_start(t: float) -> float:
	var date := Time.get_datetime_dict_from_unix_time(int(t))
	return float(Time.get_unix_time_from_datetime_dict({
		"year": date.year, "month": date.month, "day": date.day,
		"hour": 0, "minute": 0, "second": 0,
	}))

## Median of the recent run contributions; 0 when nothing is recorded yet.
func median_run_contribution() -> int:
	_load()
	if _runs.is_empty():
		return 0
	var values: Array = []
	for entry in _runs:
		values.append(int(entry.get("contribution", 0)))
	values.sort()
	@warning_ignore("integer_division")
	var middle := values.size() / 2
	if values.size() % 2 == 0:
		@warning_ignore("integer_division")
		return int((int(values[middle - 1]) + int(values[middle])) / 2)
	return int(values[middle])

func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(history_path):
		return
	var file := FileAccess.open(history_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	if data.get("snapshots") is Array:
		_snapshots = data["snapshots"]
	if data.get("events") is Array:
		_events = data["events"]
	if data.get("runs") is Array:
		_runs = data["runs"]
	if not _snapshots.is_empty():
		_last_snapshot_at = float(_snapshots[-1].get("t", -1.0))

func _save() -> void:
	var file := FileAccess.open(history_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"snapshots": _snapshots,
		"events": _events,
		"runs": _runs,
	}))
