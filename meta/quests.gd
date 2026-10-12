extends RefCounted
class_name Quests

## Daily personal quests + the conditional rivalry quest (docs/15 §4).
##
## Data-driven: the pool below defines id/kind/target/reward/title; the three
## daily slots are chosen deterministically from the UTC day seed so every client
## and every restart sees the same rotation. Progress and claims are persisted on
## `SaveManager` per UTC day. Rewards are crew points (40–150) and count toward
## the crew's daily/weekly totals; a hard local cap of 300 quest points per player
## per UTC day is enforced before any claim is dispatched.
##
## UI listens to `quests_changed` / `quest_completed`; read state with
## `active_quests()`, `daily_quests()` and `rivalry_quest()`. There is no
## autoload for this module, so use the lazy `instance()` (or any static accessor)
## to get the shared signal source.
##
## Not here: backend validation, shared crew-wide rivalry payout, cap shards.

signal quests_changed
signal quest_completed(quest: Dictionary)

## `meta/race.gd` is owned by another workstream; when it lands, `gap_to_pass` is
## used to gate the rivalry quest, otherwise the local stub below stands in.
const RACE_SCRIPT_PATH := "res://meta/race.gd"

const DAILY_COUNT := 3
const DAILY_POINT_CAP := 300
const RIVALRY_ID := "rivalry_overtake"
const RIVALRY_RUNS := 2
const RIVALRY_REWARD := 90
const QUEST_QUEUE_LIMIT := 500
## Claims drained per flush; a failed claim backs off like the run queue.
const FLUSH_BATCH := 5
const RETRY_BASE_SECONDS := 30.0
const RETRY_FACTOR := 2.0
const RETRY_MAX_SECONDS := 900.0
## Floor for "within reach" (docs/15 §3): max(150, 3 × median run contribution).
const GAP_REACH_FLOOR := 150
const STATIC_METHOD_FLAG := 32
const SECONDS_PER_DAY := 86400

const KIND_PERFECTS := "perfects"
const KIND_COMBO := "combo"
const KIND_RUNS := "runs"
const KIND_SCORE := "score"
const KIND_LANDINGS := "landings"

## Rewards stay in the 40–150 band (docs/15 §4). Targets are TESTING values.
const POOL: Array = [
	{
		"id": "perfects_10", "kind": KIND_PERFECTS, "target": 10, "reward": 120,
		"title": "Land 10 perfects", "detail": "Dead-centre landings today.",
	},
	{
		"id": "combo_x4", "kind": KIND_COMBO, "target": 4, "reward": 80,
		"title": "Reach a ×4 combo", "detail": "Stack clean landings in one run.",
	},
	{
		"id": "runs_3", "kind": KIND_RUNS, "target": 3, "reward": 60,
		"title": "Play 3 runs for your crew", "detail": "Any score counts.",
	},
	{
		"id": "score_1500", "kind": KIND_SCORE, "target": 1500, "reward": 150,
		"title": "Score 1,500 in one run", "detail": "One big run.",
	},
	{
		"id": "landings_30", "kind": KIND_LANDINGS, "target": 30, "reward": 90,
		"title": "Land 30 times", "detail": "Total landings today.",
	},
]

static var _singleton: Quests
static var _flushing: bool = false


## Shared signal source. Created on first use; stable for the process lifetime.
static func instance() -> Quests:
	if _singleton == null:
		_singleton = Quests.new()
	return _singleton


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Deterministic rotation: same UTC day -> same three quests, on every client.
static func daily_selection(utc_day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("nocaps_quests_%d" % utc_day)
	var pool: Array = POOL.duplicate(true)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var picked: Array = []
	for i in range(mini(DAILY_COUNT, pool.size())):
		picked.append(pool[i])
	return picked


## Rolls quest state onto `utc_day` when it changed (clears progress/claims and
## re-seeds the rivalry quest). `utc_day` is injectable for tests; -1 means today.
static func ensure_day(save: SaveManager, utc_day: int = -1) -> void:
	if save == null:
		return
	instance()._ensure_day(save, _resolve_day(save, utc_day))


## The three daily quests as UI-facing state dictionaries (includes rivalry).
static func active_quests(save: SaveManager, utc_day: int = -1) -> Array:
	if save == null:
		return []
	instance()._ensure_day(save, _resolve_day(save, utc_day))
	return instance()._active_quests(save)


## Only the three deterministic daily slots.
static func daily_quests(save: SaveManager, utc_day: int = -1) -> Array:
	if save == null:
		return []
	var day := _resolve_day(save, utc_day)
	instance()._ensure_day(save, day)
	var out: Array = []
	for def in daily_selection(day):
		out.append(instance()._quest_state(save, def))
	return out


## The day's rivalry quest, or `{}` when the crew is not within reach.
static func rivalry_quest(save: SaveManager, utc_day: int = -1) -> Dictionary:
	if save == null:
		return {}
	instance()._ensure_day(save, _resolve_day(save, utc_day))
	if save.quest_rivalry.is_empty():
		return {}
	return instance()._rivalry_state(save)


static func points_today(save: SaveManager) -> int:
	return int(save.quest_points_today) if save != null else 0


static func remaining_cap(save: SaveManager) -> int:
	return maxi(DAILY_POINT_CAP - points_today(save), 0)


## Feeds a finished run into quest progress. `payload` is the run-finished payload;
## missing optional keys read as 0 so the boundary stays crash-free.
static func record_run(save: SaveManager, payload: Dictionary, utc_day: int = -1) -> void:
	if save == null:
		return
	instance()._record_run(save, payload, _resolve_day(save, utc_day))


## Claims a completed quest once per UTC day, respecting the 300/day cap. Applies
## the reward as crew contribution locally and queues the claim for the backend
## (`BackendClient.claim_quest_async`, docs/15 §5). Returns a result dictionary;
## the local reward is display-only until the server confirms it.
static func claim(save: SaveManager, quest_id: String, backend: Object = null, utc_day: int = -1) -> Dictionary:
	if save == null:
		return {"ok": false, "error": "no_save"}
	return instance()._claim(save, quest_id, backend, _resolve_day(save, utc_day))


# ---------------------------------------------------------------------------
# Internal: day + state
# ---------------------------------------------------------------------------

func _ensure_day(save: SaveManager, today: int) -> void:
	if save.quest_day_utc == today:
		return
	save.quest_day_utc = today
	save.quest_progress.clear()
	save.quest_claimed.clear()
	save.quest_points_today = 0
	save.quest_rivalry = {}
	save.begin_utc_day(today)
	_seed_rivalry(save)
	save.save_data()


func _active_quests(save: SaveManager) -> Array:
	var out: Array = []
	for def in daily_selection(save.quest_day_utc):
		out.append(_quest_state(save, def))
	if not save.quest_rivalry.is_empty():
		out.append(_rivalry_state(save))
	return out


func _quest_state(save: SaveManager, def: Dictionary) -> Dictionary:
	var id := String(def.get("id", ""))
	var target := int(def.get("target", 1))
	var progress := int(save.quest_progress.get(id, 0))
	var claimed := save.quest_claimed.has(id)
	return {
		"id": id,
		"kind": String(def.get("kind", "")),
		"title": String(def.get("title", "")),
		"detail": String(def.get("detail", "")),
		"target": target,
		"reward": int(def.get("reward", 0)),
		"progress": progress,
		"completed": progress >= target,
		"claimed": claimed,
		"claimable": progress >= target and not claimed,
		"state": _state_name(claimed, progress >= target),
		"source": "daily",
		"crew_id": String(save.selected_community_id),
	}


func _rivalry_state(save: SaveManager) -> Dictionary:
	var data: Dictionary = save.quest_rivalry
	var target := int(data.get("target_runs", RIVALRY_RUNS))
	var progress := int(data.get("progress_runs", 0))
	var claimed := save.quest_claimed.has(RIVALRY_ID)
	var crew_id := String(data.get("crew_id", String(save.selected_community_id)))
	var rival_name := String(data.get("rival_name", "the crew above"))
	return {
		"id": RIVALRY_ID,
		"kind": KIND_RUNS,
		"title": "Help %s overtake %s" % [_community_name(crew_id), rival_name],
		"detail": "Play %d runs while behind." % target,
		"target": target,
		"reward": int(data.get("reward", RIVALRY_REWARD)),
		"progress": progress,
		"completed": progress >= target,
		"claimed": claimed,
		"claimable": progress >= target and not claimed,
		"state": _state_name(claimed, progress >= target),
		"source": "rivalry",
		"crew_id": crew_id,
		"rival_id": String(data.get("rival_id", "")),
		"rival_name": rival_name,
		"gap": int(data.get("gap", 0)),
	}


func _find_active(save: SaveManager, quest_id: String) -> Dictionary:
	for quest in _active_quests(save):
		if String(quest.get("id", "")) == quest_id:
			return quest
	return {}


# ---------------------------------------------------------------------------
# Internal: progress + claim
# ---------------------------------------------------------------------------

func _record_run(save: SaveManager, payload: Dictionary, today: int) -> void:
	_ensure_day(save, today)
	var selected := String(save.selected_community_id)
	var crew := String(payload.get("community_id", selected))
	var is_crew_run := selected.is_empty() or crew == selected
	# TODO(gameplay run.gd): the run payload does not yet carry perfects/max combo.
	# These keys light the perfect/combo quests up once the P2 HUD workstream adds
	# them; until then those quests simply stay at 0 progress.
	var perfects := _int_key(payload, ["perfects", "perfect_landings", "perfect"])
	var combo := _int_key(payload, ["max_combo", "max_mult", "combo"])
	var landings := _int_key(payload, ["landings"])
	var score := _int_key(payload, ["score"])

	var changed := false
	for def in daily_selection(save.quest_day_utc):
		var id := String(def.get("id", ""))
		var before := int(save.quest_progress.get(id, 0))
		var target := int(def.get("target", 1))
		var after := before
		match String(def.get("kind", "")):
			KIND_PERFECTS:
				after = before + perfects
			KIND_LANDINGS:
				after = before + landings
			KIND_RUNS:
				after = before + (1 if is_crew_run else 0)
			KIND_SCORE:
				after = maxi(before, score)
			KIND_COMBO:
				after = maxi(before, combo)
		if after != before:
			save.quest_progress[id] = after
			changed = true
		if before < target and after >= target and not save.quest_claimed.has(id):
			emit_signal("quest_completed", _quest_state(save, def))

	if not save.quest_rivalry.is_empty() and is_crew_run:
		var target := int(save.quest_rivalry.get("target_runs", RIVALRY_RUNS))
		var before := int(save.quest_rivalry.get("progress_runs", 0))
		if before < target and not save.quest_claimed.has(RIVALRY_ID):
			save.quest_rivalry["progress_runs"] = before + 1
			changed = true
			if before + 1 >= target:
				emit_signal("quest_completed", _rivalry_state(save))

	if changed:
		save.save_data()
		emit_signal("quests_changed")


func _claim(save: SaveManager, quest_id: String, backend: Object, today: int) -> Dictionary:
	_ensure_day(save, today)
	var quest := _find_active(save, quest_id)
	if quest.is_empty():
		return {"ok": false, "error": "unknown_quest"}
	if bool(quest.get("claimed", false)):
		return {"ok": false, "error": "already_claimed"}
	if not bool(quest.get("completed", false)):
		return {"ok": false, "error": "not_complete"}

	var reward := int(quest.get("reward", 0))
	var remaining := remaining_cap(save)
	if reward > remaining:
		return {"ok": false, "error": "daily_cap", "remaining": remaining}

	var crew := StringName(String(quest.get("crew_id", String(save.selected_community_id))))
	save.quest_claimed.append(quest_id)
	save.quest_points_today = int(save.quest_points_today) + reward
	var totals: Dictionary = save.record_quest_points(crew, reward)
	var claim := {
		"quest_id": quest_id,
		"utc_day": today,
		"day": _day_id(today),
		"points": reward,
		"community_id": String(crew),
		"source": "quest",
		"created_at": int(Time.get_unix_time_from_system()),
	}
	_dispatch_claim(save, backend, claim)
	save.save_data()
	emit_signal("quests_changed")
	return {
		"ok": true,
		"quest_id": quest_id,
		"points": reward,
		"remaining": remaining - reward,
		"day_total": int(totals.get("day_total", 0)),
		"week_total": int(totals.get("week_total", 0)),
		"claim": claim,
	}


## Queues the claim durably, then attempts an immediate server commit when the
## backend exposes `claim_quest_async` (docs/15 §5). The server is authoritative:
## the local reward is display-only until the commit lands. A failed attempt stays
## queued and is retried by `flush_async` after sign-in/reconnect.
func _dispatch_claim(save: SaveManager, backend: Object, claim: Dictionary) -> void:
	_enqueue_claim(save, claim)
	if backend != null and backend.has_method("claim_quest_async"):
		flush_async(save, backend)


## Adds a claim to the pending queue once, bounded like the run queue. Keyed by
## quest + day + crew so a retry never double-queues the same claim.
func _enqueue_claim(save: SaveManager, claim: Dictionary) -> void:
	var key := _claim_key(claim)
	for entry in save.pending_quest_claims:
		if _claim_key(entry.get("claim", {})) == key:
			return
	while save.pending_quest_claims.size() >= QUEST_QUEUE_LIMIT:
		save.pending_quest_claims.remove_at(0)
	save.pending_quest_claims.append({
		"claim": claim,
		"attempts": 0,
		"next_attempt_at": 0.0,
		"last_error": "",
	})


## Drains due queued claims through `BackendClient.claim_quest_async`, removing a
## claim once the server confirms it (a duplicate/ALREADY_EXISTS is also done, so
## the same claim is never double-counted). Failures back off. Callable after
## sign-in/reconnect and right after a claim; `on_done` receives
## `{attempted, submitted, pending, error}`.
static func flush_async(save: SaveManager, client: Object, on_done: Callable = Callable()) -> void:
	if save == null or client == null or not client.has_method("claim_quest_async"):
		if on_done.is_valid():
			on_done.call(_flush_summary(save, 0, 0, "offline"))
		return
	if _flushing:
		if on_done.is_valid():
			on_done.call(_flush_summary(save, 0, 0, "busy"))
		return
	var now_s := Time.get_unix_time_from_system()
	var batch: Array = []
	for entry in save.pending_quest_claims:
		if batch.size() >= FLUSH_BATCH:
			break
		if float(entry.get("next_attempt_at", 0.0)) <= now_s:
			batch.append(entry)
	if batch.is_empty():
		if on_done.is_valid():
			on_done.call(_flush_summary(save, 0, 0, ""))
		return
	_flushing = true
	var state := {"remaining": batch.size(), "submitted": 0, "error": ""}
	for entry in batch:
		var claim: Dictionary = entry.get("claim", {})
		var key := _claim_key(claim)
		client.claim_quest_async(
			String(claim.get("quest_id", "")),
			int(claim.get("points", 0)),
			String(claim.get("community_id", "")),
			func(result: Dictionary) -> void:
				if bool(result.get("ok", false)):
					state["submitted"] = int(state["submitted"]) + 1
					_remove_queued(save, key)
				else:
					state["error"] = String(result.get("error", "unknown"))
					_backoff_queued(save, key, now_s, String(state["error"]))
				state["remaining"] = int(state["remaining"]) - 1
				if int(state["remaining"]) <= 0:
					_flushing = false
					save.save_data()
					# Server is the source of truth: drop cached rows so the standings
					# refresh picks up the confirmed points.
					if int(state["submitted"]) > 0:
						Standings.clear_cache()
					if on_done.is_valid():
						on_done.call(_flush_summary(save, batch.size(), int(state["submitted"]), String(state["error"])))
					# A claim enqueued while this batch was in flight is picked up
					# here; backed-off entries are not due, so this cannot spin.
					if not save.pending_quest_claims.is_empty():
						flush_async(save, client)
		)


static func _flush_summary(save: SaveManager, attempted: int, submitted: int, error: String) -> Dictionary:
	return {
		"attempted": attempted,
		"submitted": submitted,
		"pending": save.pending_quest_claims.size() if save != null else 0,
		"error": error,
	}


static func _claim_key(claim: Dictionary) -> String:
	return "%s:%s:%s" % [
		String(claim.get("quest_id", "")),
		String(claim.get("day", claim.get("utc_day", ""))),
		String(claim.get("community_id", "")),
	]


static func _remove_queued(save: SaveManager, key: String) -> void:
	for i in range(save.pending_quest_claims.size() - 1, -1, -1):
		if _claim_key(save.pending_quest_claims[i].get("claim", {})) == key:
			save.pending_quest_claims.remove_at(i)
			return


static func _backoff_queued(save: SaveManager, key: String, now_s: float, error: String) -> void:
	for entry in save.pending_quest_claims:
		if _claim_key(entry.get("claim", {})) == key:
			entry["attempts"] = int(entry.get("attempts", 0)) + 1
			entry["last_error"] = error
			var delay: float = minf(
				RETRY_BASE_SECONDS * pow(RETRY_FACTOR, float(entry["attempts"]) - 1.0),
				RETRY_MAX_SECONDS
			)
			entry["next_attempt_at"] = now_s + delay
			return


# ---------------------------------------------------------------------------
# Internal: rivalry seeding + gap-to-pass
# ---------------------------------------------------------------------------

## Seeds the day's rivalry quest when the player's crew is within reach of the
## crew directly above it. Uses `meta/race.gd::gap_to_pass` when available.
func _seed_rivalry(save: SaveManager) -> void:
	if String(save.selected_community_id).is_empty():
		return
	var rows: Array = Standings.communities_today(save)
	var gap := _gap_to_pass(save, rows)
	if gap <= 0:
		return
	var rival := _crew_above(save, rows)
	if rival.is_empty():
		return
	save.quest_rivalry = {
		"id": RIVALRY_ID,
		"crew_id": String(save.selected_community_id),
		"rival_id": String(rival.get("id", "")),
		"rival_name": String(rival.get("name", "the crew above")),
		"target_runs": RIVALRY_RUNS,
		"progress_runs": 0,
		"reward": RIVALRY_REWARD,
		"gap": gap,
	}


## Prefers `meta/race.gd::gap_to_pass(rows, my_id)` (static or instance) and falls
## back to the local stub while that module is being built. `Race` returns the
## target crew dictionary; we reduce it to the positive gap (or -1 when hidden).
func _gap_to_pass(save: SaveManager, rows: Array) -> int:
	if ResourceLoader.exists(RACE_SCRIPT_PATH):
		var script: Variant = load(RACE_SCRIPT_PATH)
		if script != null:
			var info := _find_method(script, "gap_to_pass")
			if not info.is_empty():
				var args: Array = info.get("args", [])
				var is_static := (int(info.get("flags", 0)) & STATIC_METHOD_FLAG) != 0
				if not is_static and not script.can_instantiate():
					return _stub_gap_to_pass(save, rows)
				var target: Object = script if is_static else script.new()
				var my_id := String(save.selected_community_id)
				var gap: Variant
				if args.size() >= 2:
					gap = target.call("gap_to_pass", rows, my_id)
				elif args.size() == 1:
					gap = target.call("gap_to_pass", rows)
				else:
					gap = target.call("gap_to_pass")
				if gap is Dictionary:
					var target_row: Dictionary = gap
					if String(target_row.get("id", "")).is_empty():
						return -1
					return int(target_row.get("gap", -1))
				if gap is int or gap is float:
					return int(gap)
	return _stub_gap_to_pass(save, rows)


## TODO(race): replace once `meta/race.gd::gap_to_pass` exists. Approximates the
## docs/15 §3 threshold max(150, 3 × median run contribution) with the average
## contribution because per-run contributions are not retained.
func _stub_gap_to_pass(save: SaveManager, rows: Array) -> int:
	var mine := _crew_row(save, rows)
	var above := _crew_above(save, rows)
	if mine.is_empty() or above.is_empty():
		return -1
	var gap := int(above.get("score", 0)) - int(mine.get("score", 0))
	if gap <= 0:
		return -1
	var reach := maxi(GAP_REACH_FLOOR, 3 * _average_run_contribution(save))
	return gap if gap <= reach else -1


func _average_run_contribution(save: SaveManager) -> int:
	if save == null or save.runs_played <= 0:
		return 0
	return int(save.total_contribution(save.selected_community_id) / save.runs_played)


func _crew_row(save: SaveManager, rows: Array) -> Dictionary:
	var id := String(save.selected_community_id)
	for row in rows:
		if row is Dictionary and String(row.get("id", "")) == id:
			return row
	return {}


func _crew_above(save: SaveManager, rows: Array) -> Dictionary:
	var index := -1
	for i in range(rows.size()):
		if rows[i] is Dictionary and String(rows[i].get("id", "")) == String(save.selected_community_id):
			index = i
			break
	if index <= 0:
		return {}
	return rows[index - 1]


func _find_method(script: Variant, method: String) -> Dictionary:
	for info in script.get_script_method_list():
		if String(info.get("name", "")) == method:
			return info
	return {}


# ---------------------------------------------------------------------------
# Internal: helpers
# ---------------------------------------------------------------------------

static func _resolve_day(save: SaveManager, utc_day: int) -> int:
	return utc_day if utc_day >= 0 else save.current_utc_day()


func _int_key(payload: Dictionary, keys: Array) -> int:
	for key in keys:
		if payload.has(key):
			return int(payload.get(key, 0))
	return 0


func _state_name(claimed: bool, completed: bool) -> String:
	if claimed:
		return "claimed"
	return "complete" if completed else "active"


func _community_name(id: String) -> String:
	if id.is_empty():
		return "your crew"
	var community := CommunityRepository.by_id(CommunityRepository.load_roster(), StringName(id))
	return community.display_name if community != null else id


func _day_id(today: int) -> String:
	return Time.get_datetime_string_from_unix_time(today * SECONDS_PER_DAY, true).substr(0, 10)
