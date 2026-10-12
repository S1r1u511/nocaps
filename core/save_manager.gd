extends Node
class_name SaveManager

## Local, versioned player save. Owns offline facts: selected community, bests,
## player settings, local streak/week contribution bookkeeping, and the pending
## submission queue. Verified leaderboard data lives in the backend, never here.
## See docs/03_ARCHITECTURE.md §10 and docs/10_BACKEND.md.

const DEFAULT_SAVE_PATH := "user://nocaps_v1.json"
const SCHEMA_VERSION := 2
const SECONDS_PER_DAY := 86400

var save_path: String = DEFAULT_SAVE_PATH
var selected_community_id: StringName = &""
var best_score: int = 0
## Lifetime in-game currency (coins collected across runs). Currency only: this
## never feeds score, contribution, or bests.
var coins_total: int = 0
## Longest single-run survival time in seconds (playtest_v05 metric).
var best_time: float = 0.0
var player_id: String = ""
var display_name: String = ""
## The result-screen "put your name on the board" card was skipped.
var name_prompt_dismissed: bool = false
## Preview reward claims ("<crew>:<tier>" -> unix time). Local until rewards are server-backed.
var reward_claims: Dictionary = {}
var runs_played: int = 0
## v2 profile stat; kept in sync with `runs_played` and derived on load if absent.
var games_played: int = 0
var muted: bool = false
var haptics_enabled: bool = true
var reduced_motion: bool = false
var tutorial_seen: bool = false

## Caps the player has unlocked by joining/repping a crew (community ids).
var unlocked_caps: Array = []
## Caps unlocked for crews that reached weekly tier 3 (community ids).
var rare_caps: Array = []

## Local community progress. Provisional until the backend is authoritative.
var contribution_by_community: Dictionary = {}
var week_contribution: Dictionary = {}
var tiers_reached: Dictionary = {}
var best_by_community: Dictionary = {}
var week_best: Dictionary = {}
var day_contribution: Dictionary = {}
var day_best: Dictionary = {}
## UTC day numbers (days since the Unix epoch). The server owns period boundaries.
var week_start_day_utc: int = 0
var day_start_day_utc: int = 0
var last_played_day_utc: int = 0
var streak_days: int = 0
## Queued run records awaiting backend submission (Phase 4.2).
var pending_submissions: Array = []
## Wallet address the server verified for this player (linkWallet), or "".
var verified_wallet: String = ""
## Runs dropped because the offline queue was full (never silent; see run_submission.gd).
var dropped_runs: int = 0
## Quests (docs/15 §4). Per-UTC-day state owned by `meta/quests.gd`.
var quest_day_utc: int = 0
var quest_progress: Dictionary = {}
var quest_claimed: Array = []
var quest_points_today: int = 0
var quest_rivalry: Dictionary = {}
## Quest claims queued for the backend until `BackendClient.claim_quest` lands.
var pending_quest_claims: Array = []

func _ready() -> void:
	load_data()

## Safe save (Oct 10, fundamentals E12): the save is written to `.tmp`, the
## previous good file is kept as `.bak`, then `.tmp` replaces the main file. A
## kill mid-write leaves either the old file, the `.bak` or the `.tmp` intact.
func load_data() -> void:
	var data := _read_first_valid([save_path, save_path + ".bak", save_path + ".tmp"])
	if data.is_empty():
		return
	selected_community_id = StringName(data.get("selected_community_id", ""))
	best_score = int(data.get("best_score", 0))
	coins_total = int(data.get("coins_total", 0))
	best_time = float(data.get("best_time", 0.0))
	player_id = String(data.get("player_id", ""))
	display_name = String(data.get("display_name", ""))
	name_prompt_dismissed = bool(data.get("name_prompt_dismissed", false))
	var claims: Variant = data.get("reward_claims", {})
	reward_claims = claims if claims is Dictionary else {}
	runs_played = int(data.get("runs_played", 0))
	games_played = int(data.get("games_played", runs_played))
	muted = bool(data.get("muted", false))
	haptics_enabled = bool(data.get("haptics_enabled", true))
	reduced_motion = bool(data.get("reduced_motion", false))
	tutorial_seen = bool(data.get("tutorial_seen", false))
	unlocked_caps = _as_string_array(data.get("unlocked_caps", []))
	rare_caps = _as_string_array(data.get("rare_caps", []))
	contribution_by_community = _as_dictionary(data.get("contribution_by_community", {}))
	week_contribution = _as_dictionary(data.get("week_contribution", {}))
	tiers_reached = _as_dictionary(data.get("tiers_reached", {}))
	best_by_community = _as_dictionary(data.get("best_by_community", {}))
	week_best = _as_dictionary(data.get("week_best", {}))
	day_contribution = _as_dictionary(data.get("day_contribution", {}))
	day_best = _as_dictionary(data.get("day_best", {}))
	week_start_day_utc = int(data.get("week_start_day_utc", 0))
	day_start_day_utc = int(data.get("day_start_day_utc", 0))
	last_played_day_utc = int(data.get("last_played_day_utc", 0))
	streak_days = int(data.get("streak_days", 0))
	pending_submissions = data.get("pending_submissions", []) if data.get("pending_submissions", []) is Array else []
	dropped_runs = int(data.get("dropped_runs", 0))
	verified_wallet = String(data.get("verified_wallet", ""))
	quest_day_utc = int(data.get("quest_day_utc", 0))
	quest_progress = _as_dictionary(data.get("quest_progress", {}))
	quest_claimed = _as_string_array(data.get("quest_claimed", []))
	quest_points_today = int(data.get("quest_points_today", 0))
	quest_rivalry = _as_dictionary(data.get("quest_rivalry", {}))
	pending_quest_claims = data.get("pending_quest_claims", []) if data.get("pending_quest_claims", []) is Array else []
	_derive_caps()
	if int(data.get("schema_version", 1)) < 2:
		_migrate_to_v2()

func save_data() -> void:
	var data := {
		"schema_version": SCHEMA_VERSION,
		"selected_community_id": String(selected_community_id),
		"best_score": best_score,
		"coins_total": coins_total,
		"best_time": best_time,
		"player_id": player_id,
		"display_name": display_name,
		"name_prompt_dismissed": name_prompt_dismissed,
		"reward_claims": reward_claims,
		"runs_played": runs_played,
		"games_played": games_played,
		"muted": muted,
		"haptics_enabled": haptics_enabled,
		"reduced_motion": reduced_motion,
		"tutorial_seen": tutorial_seen,
		"unlocked_caps": unlocked_caps,
		"rare_caps": rare_caps,
		"contribution_by_community": contribution_by_community,
		"week_contribution": week_contribution,
		"tiers_reached": tiers_reached,
		"best_by_community": best_by_community,
		"week_best": week_best,
		"day_contribution": day_contribution,
		"day_best": day_best,
		"week_start_day_utc": week_start_day_utc,
		"day_start_day_utc": day_start_day_utc,
		"last_played_day_utc": last_played_day_utc,
		"streak_days": streak_days,
		"pending_submissions": pending_submissions,
		"dropped_runs": dropped_runs,
		"verified_wallet": verified_wallet,
		"quest_day_utc": quest_day_utc,
		"quest_progress": quest_progress,
		"quest_claimed": quest_claimed,
		"quest_points_today": quest_points_today,
		"quest_rivalry": quest_rivalry,
		"pending_quest_claims": pending_quest_claims,
	}
	var tmp_path := save_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: cannot write save file")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(save_path, save_path + ".bak")
	var err := DirAccess.rename_absolute(tmp_path, save_path)
	if err != OK:
		push_warning("SaveManager: could not replace save file (error %d)" % err)

## Returns the first file in `paths` that parses as a JSON object, or {}.
func _read_first_valid(paths: Array) -> Dictionary:
	for i in paths.size():
		var path := String(paths[i])
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			if i > 0:
				push_warning("SaveManager: main save unreadable; restored from %s" % path.get_file())
			return parsed
	if FileAccess.file_exists(save_path):
		push_warning("SaveManager: save file is corrupt and no backup is readable; using defaults")
	return {}

func set_selected_community(id: StringName) -> void:
	selected_community_id = id
	_unlock_cap(id)
	save_data()

## Stable local guest identity until a wallet is linked.
func ensure_player_id() -> String:
	if player_id.is_empty():
		player_id = "guest-%d-%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
		save_data()
	return player_id

## Banks a finished run locally: advances the streak, adds contribution, updates
## bests (score and survival time), and records crossed weekly tiers. Returns a
## breakdown for the Result screen. `utc_day` / `utc_week_start` are injectable
## for tests; -1 means "now".
func record_run(
	community_id: StringName,
	tiers: PackedInt32Array,
	score: int,
	_landings: int,
	duration: float,
	utc_day: int = -1,
	utc_week_start: int = -1
) -> Dictionary:
	var today := utc_day if utc_day >= 0 else current_utc_day()
	var week_start := utc_week_start if utc_week_start >= 0 else week_start_for(today)
	if week_start != week_start_day_utc:
		week_start_day_utc = week_start
		week_contribution.clear()
		tiers_reached.clear()
		week_best.clear()
	if today != day_start_day_utc:
		day_start_day_utc = today
		day_contribution.clear()
		day_best.clear()

	var streak := _touch_streak(today)
	var multiplier := Scoring.streak_multiplier(streak)
	var contribution := Scoring.contribution_for(score, streak)
	runs_played += 1
	games_played += 1
	var key := String(community_id)
	contribution_by_community[key] = int(contribution_by_community.get(key, 0)) + contribution
	week_contribution[key] = int(week_contribution.get(key, 0)) + contribution
	day_contribution[key] = int(day_contribution.get(key, 0)) + contribution
	best_by_community[key] = maxi(int(best_by_community.get(key, 0)), score)
	week_best[key] = maxi(int(week_best.get(key, 0)), score)
	day_best[key] = maxi(int(day_best.get(key, 0)), score)
	if score > best_score:
		best_score = score
	if duration > best_time:
		best_time = duration

	var before := int(tiers_reached.get(key, 0))
	var after := Scoring.tier_index(int(week_contribution[key]), tiers)
	if after > before:
		tiers_reached[key] = after
	_unlock_cap(community_id)
	if after >= 3:
		_unlock_rare_cap(community_id)
	save_data()

	return {
		"contribution": contribution,
		"streak": streak,
		"streak_multiplier": multiplier,
		"week_total": int(week_contribution[key]),
		"day_total": int(day_contribution[key]),
		"tier_before": before,
		"tier_after": after,
		"tier_crossed": after > before,
	}

## Banks coins collected in a run. Currency only: deliberately separate from
## `record_run`, so it can never touch score, bests, or contribution. Returns
## the new lifetime total.
func record_coins(amount: int) -> int:
	coins_total += maxi(amount, 0)
	save_data()
	return coins_total

## Adds quest reward points as crew contribution (`source: quest`, docs/15 §4).
## Deliberately separate from `record_run`: quest points never touch score/best or
## the streak multiplier. Keeps daily/weekly/all-time totals consistent with runs.
func record_quest_points(community_id: StringName, points: int) -> Dictionary:
	var key := String(community_id)
	var amount := maxi(points, 0)
	if key.is_empty() or amount == 0:
		return {"day_total": day_total(community_id), "week_total": week_total(community_id)}
	contribution_by_community[key] = int(contribution_by_community.get(key, 0)) + amount
	week_contribution[key] = int(week_contribution.get(key, 0)) + amount
	day_contribution[key] = int(day_contribution.get(key, 0)) + amount
	save_data()
	return {"day_total": int(day_contribution[key]), "week_total": int(week_contribution[key])}

## Advances the local daily boundary when a new UTC day starts without a run
## (quest claims on a fresh day). Keeps daily totals on the same boundary as
## `record_run`; a no-op within the same day.
func begin_utc_day(today: int) -> void:
	if today == day_start_day_utc:
		return
	day_start_day_utc = today
	day_contribution.clear()
	day_best.clear()
	save_data()

func total_contribution(id: StringName) -> int:
	return int(contribution_by_community.get(String(id), 0))

func week_total(id: StringName) -> int:
	return int(week_contribution.get(String(id), 0))

func day_total(id: StringName) -> int:
	return int(day_contribution.get(String(id), 0))

func best_for(id: StringName) -> int:
	return int(best_by_community.get(String(id), 0))

func week_best_for(id: StringName) -> int:
	return int(week_best.get(String(id), 0))

func day_best_for(id: StringName) -> int:
	return int(day_best.get(String(id), 0))

func tiers_crossed(id: StringName) -> int:
	return int(tiers_reached.get(String(id), 0))

func has_unlocked_cap(id: StringName) -> bool:
	return unlocked_caps.has(String(id))

func has_rare_cap(id: StringName) -> bool:
	return rare_caps.has(String(id))

## Tiers reached for a community's current week total.
func tier_for(id: StringName, tiers: PackedInt32Array) -> int:
	return Scoring.tier_index(week_total(id), tiers)

## Clears all local progress and settings (Profile → Reset local data).
func reset_all() -> void:
	selected_community_id = &""
	best_score = 0
	coins_total = 0
	best_time = 0.0
	display_name = ""
	name_prompt_dismissed = false
	reward_claims = {}
	runs_played = 0
	games_played = 0
	muted = false
	haptics_enabled = true
	reduced_motion = false
	tutorial_seen = false
	unlocked_caps.clear()
	rare_caps.clear()
	contribution_by_community.clear()
	week_contribution.clear()
	tiers_reached.clear()
	best_by_community.clear()
	week_best.clear()
	day_contribution.clear()
	day_best.clear()
	week_start_day_utc = 0
	day_start_day_utc = 0
	last_played_day_utc = 0
	streak_days = 0
	pending_submissions.clear()
	dropped_runs = 0
	quest_day_utc = 0
	quest_progress.clear()
	quest_claimed.clear()
	quest_points_today = 0
	quest_rivalry.clear()
	pending_quest_claims.clear()
	save_data()

## --- Time helpers (UTC; the server owns period boundaries) ---

func current_utc_day() -> int:
	return ServerClock.day_number()

func week_start_for(utc_day: int) -> int:
	var weekday := int(Time.get_datetime_dict_from_unix_time(utc_day * SECONDS_PER_DAY).get("weekday", 0))
	return utc_day - (weekday + 6) % 7

func week_start_date() -> String:
	return Time.get_datetime_string_from_unix_time(week_start_day_utc * SECONDS_PER_DAY, true).substr(0, 10)

func _touch_streak(today: int) -> int:
	if today == last_played_day_utc:
		pass
	elif today == last_played_day_utc + 1:
		streak_days += 1
		last_played_day_utc = today
	else:
		streak_days = 1
		last_played_day_utc = today
	if streak_days < 1:
		streak_days = 1
	return streak_days

func _migrate_to_v2() -> void:
	if selected_community_id != &"" and not best_by_community.has(String(selected_community_id)):
		best_by_community[String(selected_community_id)] = best_score
	save_data()

## Backfills cap unlocks from existing contribution/tier data when the v2 fields
## are absent. See docs/UI_V2_BRIEF.md §4.
func _derive_caps() -> void:
	if unlocked_caps.is_empty():
		for key in contribution_by_community.keys():
			if int(contribution_by_community[key]) > 0:
				_unlock_cap(StringName(key))
		if selected_community_id != &"":
			_unlock_cap(selected_community_id)
	if rare_caps.is_empty():
		for key in tiers_reached.keys():
			if int(tiers_reached[key]) >= 3:
				_unlock_rare_cap(StringName(key))

func _unlock_cap(id: StringName) -> void:
	var key := String(id)
	if key.is_empty() or unlocked_caps.has(key):
		return
	unlocked_caps.append(key)

func _unlock_rare_cap(id: StringName) -> void:
	var key := String(id)
	if key.is_empty() or rare_caps.has(key):
		return
	rare_caps.append(key)

func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

func _as_string_array(value: Variant) -> Array:
	if not value is Array:
		return []
	var out: Array = []
	for entry in value:
		out.append(String(entry))
	return out
