extends RefCounted
class_name Standings

## Today's community race: one ranked row per enabled community, zeros included.
## Home, Board, Explore, and Result read crew standings only from here.
## Live backend rows are cached and refreshed at most once every 10 seconds by
## `communities_today`; unresolved communities stay at 0 and a missing/offline
## backend silently falls back to the local day contribution. The last successful
## rows are also mirrored to `user://` so a launch can render the board instantly
## from the previous session while the boot fetch refreshes it.
##
## Competition layer (docs/15_COMPETITION_AND_QUESTS.md §2–3): `communities_week`,
## crew player rankings/rank/top carriers, member counts, and the last champion
## are served from the same place with 60 s caches; every `communities_today`
## render feeds `meta/race.gd` a momentum/event snapshot.

const REFRESH_SECONDS := 10.0

## How long a successful leaderboard fetch keeps the UI in the "live" state.
## Screens no longer poll, so "live" means: the most recent fetch succeeded and
## finished less than LIVE_SECONDS ago (Oct 10).
const LIVE_SECONDS := 600.0

## Slower-moving crew data (players, members, champion, weekly totals).
const CREW_CACHE_SECONDS := 60.0

## Last successful rows for the current UTC day, mirrored for instant launch paint.
const CACHE_PATH := "user://standings_cache.json"
## Last known slow-moving crew values (member counts), so a cold launch shows the
## previous numbers instead of 0 while the fresh fetch runs.
const CREW_SNAPSHOT_PATH := "user://standings_crew_snapshot.json"

## Cached backend community rows for the current UTC day.
static var _remote_rows: Array = []
static var _remote_period_id: String = ""
static var _last_fetch_at: float = -REFRESH_SECONDS
static var _last_success_at: float = -1.0
static var _last_result_at: float = -1.0
static var _fetching: bool = false
static var _cache_loaded: bool = false
static var _first_live_at_ms: int = -1

## Weekly crew rows and the 60 s crew caches.
static var _weekly_rows: Array = []
static var _weekly_period_id: String = ""
static var _weekly_fetched_at: float = -1.0
static var _weekly_fetching: bool = false
static var _crew_cache: Dictionary = {}
static var _race: Race = null
static var _snapshot: Dictionary = {}
static var _snapshot_loaded: bool = false

## Bumped whenever new backend data lands (daily, weekly, crew caches). Screens
## watch it instead of polling the network (Oct 10, E10).
static var _version: int = 0

static func version() -> int:
	return _version

## Shared race state (momentum, overtakes, countdown). Lazily created so tests can
## instantiate `Race` directly with their own history path.
static func race_state() -> Race:
	if _race == null:
		_race = Race.new()
	return _race

## Backend connection shown on the standings UI:
## "live" — a successful fetch finished less than LIVE_SECONDS ago;
## "connecting" — a usable backend exists but no fetch has completed yet;
## "offline" — no usable backend, or the last completed fetch failed/is stale.
static func connection_state() -> String:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_success_at >= 0.0 and _last_success_at >= _last_result_at and now - _last_success_at < LIVE_SECONDS:
		return "live"
	var backend := BackendClient.instance
	if backend == null or not backend.is_available():
		return "offline"
	if _last_result_at < 0.0:
		return "connecting"
	return "offline"

## Sorted rows: [{id, name, score, rank, community}], highest score first.
static func communities_today(save_manager: SaveManager) -> Array:
	_ensure_cache_loaded()
	_maybe_refresh()
	var have_remote := _remote_period_id == _today_id()
	var remote := _remote_scores()
	var pending := _pending_by_crew(save_manager, false)
	var rows: Array = []
	for community in CommunityRepository.enabled_sorted(CommunityRepository.load_roster_lite()):
		if community == null:
			continue
		rows.append({
			"id": community.id,
			"name": community.display_name,
			"score": _merged_score(have_remote, remote, pending, community.id,
				save_manager.day_total(community.id) if save_manager != null else 0),
			"rank": 0,
			"community": community,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a["score"])
		var right := int(b["score"])
		if left == right:
			return String(a["id"]) < String(b["id"])
		return left > right)
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
	race_state().observe(rows)
	return rows

## Ranked weekly rows: [{id, name, score, rank, community}]. Same contract as
## `communities_today`, refreshed once a minute.
static func communities_week(save_manager: SaveManager) -> Array:
	_maybe_refresh_weekly()
	var have_remote := _weekly_period_id == _week_id()
	var remote := _remote_weekly_scores()
	var pending := _pending_by_crew(save_manager, true)
	var rows: Array = []
	for community in CommunityRepository.enabled_sorted(CommunityRepository.load_roster_lite()):
		if community == null:
			continue
		rows.append({
			"id": community.id,
			"name": community.display_name,
			"score": _merged_score(have_remote, remote, pending, community.id,
				save_manager.week_total(community.id) if save_manager != null else 0),
			"rank": 0,
			"community": community,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a["score"])
		var right := int(b["score"])
		if left == right:
			return String(a["id"]) < String(b["id"])
		return left > right)
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
	return rows

## Top 3 crews plus the player's crew when it sits outside the top 3; the extra
## row is flagged `mine: true`.
static func top3_plus_mine(save_manager: SaveManager, my_community_id: StringName) -> Array:
	var rows := communities_today(save_manager)
	var out: Array = []
	for i in range(mini(3, rows.size())):
		out.append(rows[i])
	if my_community_id == &"":
		return out
	for i in range(out.size()):
		if String(out[i]["id"]) == String(my_community_id):
			return out
	for row in rows:
		if String(row["id"]) == String(my_community_id):
			var mine: Dictionary = row.duplicate()
			mine["mine"] = true
			out.append(mine)
			return out
	return out

## Top players of one crew for a period (highest first). Each row:
## {uid, name, score, runs, rank, you}. Cached 60 s; offline it returns the local
## player row only.
static func crew_players(save_manager: SaveManager, community_id: StringName, period: StringName = &"weekly") -> Array:
	var key := "players:%s:%s" % [community_id, period]
	_maybe_fetch_crew(key, community_id, period)
	var cached: Variant = _cache_get(key)
	if cached != null:
		return cached
	return _local_crew_rows(save_manager, community_id, period)

## Player's rank inside their crew (1-based), or 0 while unknown/offline.
static func my_rank_in_crew(save_manager: SaveManager, community_id: StringName, period: StringName = &"weekly") -> int:
	var me := _my_uid()
	for row in crew_players(save_manager, community_id, period):
		if bool(row.get("you", false)) or (not me.is_empty() and String(row.get("uid", "")) == me):
			return int(row.get("rank", 0))
	return 0

## MVP, #2 and the player (top 2 + "You", deduped), highest first.
static func top_carriers(save_manager: SaveManager, community_id: StringName, period: StringName = &"weekly") -> Array:
	var players := crew_players(save_manager, community_id, period)
	var out: Array = []
	var included_me := false
	for row in players:
		var is_me := bool(row.get("you", false))
		if is_me:
			included_me = true
		if out.size() < 2 or is_me:
			out.append(row)
		if out.size() >= 3:
			break
	if not included_me:
		var local := _local_crew_rows(save_manager, community_id, period)
		if not local.is_empty() and out.size() < 3:
			out.append(local[0])
	return out

## Member count for a crew (COUNT aggregation, cached 60 s). Falls back to the
## last known count from a previous session; 0 only while truly unknown.
static func members_count(community_id: StringName) -> int:
	var key := "members:%s" % community_id
	_maybe_fetch_members(key, community_id)
	var cached: Variant = _cache_get(key)
	if cached != null:
		return int(cached)
	return int(_snapshot_get(key, 0))

## True once a member count is known (fresh or from the last session).
static func members_known(community_id: StringName) -> bool:
	var key := "members:%s" % community_id
	return _cache_get(key) != null or _snapshot_get(key, null) != null

## True when the board can paint real rows right now (live or last session's).
static func has_rows() -> bool:
	_ensure_cache_loaded()
	return not _remote_rows.is_empty() and _remote_period_id == _today_id()

static func _snapshot_get(key: String, fallback: Variant) -> Variant:
	if not _snapshot_loaded:
		_snapshot_loaded = true
		if FileAccess.file_exists(CREW_SNAPSHOT_PATH):
			var file := FileAccess.open(CREW_SNAPSHOT_PATH, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed is Dictionary:
					_snapshot = parsed
	return _snapshot.get(key, fallback)

static func _snapshot_set(key: String, value: Variant) -> void:
	_snapshot_get(key, null)
	_snapshot[key] = value
	var file := FileAccess.open(CREW_SNAPSHOT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_snapshot))

## Most recent closed-period champion for a crew, or {} while unknown/offline.
static func last_champion(community_id: StringName) -> Dictionary:
	var key := "champion:%s" % community_id
	_maybe_fetch_champion(key, community_id)
	var cached: Variant = _cache_get(key)
	return cached if cached is Dictionary else {}

## Clears the crew caches (tests, account changes). Leaves the daily board cache
## alone; call `clear_cache` for that.
static func clear_crew_cache() -> void:
	_crew_cache.clear()
	_weekly_rows = []
	_weekly_period_id = ""
	_weekly_fetched_at = -1.0

## Boot warm-up: paint from the on-disk cache and start the first fetch before the
## player opens any screen, so the board is ready (or already live) on first view.
## Anonymous sign-in is started by `BackendClient` at boot; the fetch shares it.
static func warm_up(backend: BackendClient) -> void:
	_ensure_cache_loaded()
	if backend == null or not backend.is_available():
		return
	_maybe_refresh()

## Explicit refresh for screens that want to await the round trip, then hands the
## merged standings to `callback`. Offline it calls back with local rows.
static func refresh_today(backend: BackendClient, save_manager: SaveManager, callback: Callable = Callable()) -> void:
	if backend == null or not backend.is_available() or _fetching:
		if callback.is_valid():
			callback.call(communities_today(save_manager))
		return
	_fetching = true
	_last_fetch_at = Time.get_ticks_msec() / 1000.0
	backend.fetch_leaderboard_async(&"communities", &"daily", func(result: Dictionary) -> void:
		_fetching = false
		_absorb(result)
		if callback.is_valid():
			callback.call(communities_today(save_manager)))

## Clears the cache (tests, account changes).
static func clear_cache() -> void:
	_remote_rows = []
	_remote_period_id = ""
	_last_fetch_at = -REFRESH_SECONDS
	_last_success_at = -1.0
	_last_result_at = -1.0
	_fetching = false
	_cache_loaded = false
	_first_live_at_ms = -1
	_snapshot = {}
	_snapshot_loaded = false
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)
	if FileAccess.file_exists(CREW_SNAPSHOT_PATH):
		DirAccess.remove_absolute(CREW_SNAPSHOT_PATH)

## Background refresh driven by `communities_today`, throttled to REFRESH_SECONDS.
static func _maybe_refresh() -> void:
	if _fetching:
		return
	var backend := BackendClient.instance
	if backend == null or not backend.is_available():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_fetch_at < REFRESH_SECONDS:
		return
	_last_fetch_at = now
	_fetching = true
	backend.fetch_leaderboard_async(&"communities", &"daily", func(result: Dictionary) -> void:
		_fetching = false
		_absorb(result))

static func _absorb(result: Dictionary) -> void:
	_version += 1
	_last_result_at = Time.get_ticks_msec() / 1000.0
	if bool(result.get("ok", false)):
		_remote_rows = result.get("rows", [])
		_remote_period_id = String(result.get("periodId", ""))
		_last_success_at = _last_result_at
		_write_cache()
		if _first_live_at_ms < 0:
			_first_live_at_ms = int(Time.get_ticks_msec())
			print("[standings] first live rows (%d) at %d ms" % [_remote_rows.size(), _first_live_at_ms])

## Loads the previous session's rows once; they paint immediately but do not mark
## the connection "live" — only a fresh fetch does that.
static func _ensure_cache_loaded() -> void:
	if _cache_loaded:
		return
	_cache_loaded = true
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var period_id := String(parsed.get("periodId", ""))
	if period_id.is_empty() or period_id != _today_id():
		return
	var rows: Variant = parsed.get("rows", [])
	if rows is Array:
		_remote_rows = rows
		_remote_period_id = period_id

static func _write_cache() -> void:
	if _remote_period_id.is_empty():
		return
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"periodId": _remote_period_id, "rows": _remote_rows}))

## One source of truth: once the backend has answered for this period (live or
## from today's cache), its number is the score — the same number the web shows —
## plus this device's runs that are still waiting in the submission queue.
## The device's own running total is only a fallback while nothing has loaded
## yet (first launch offline). Taking max(local, remote) made the phone disagree
## with the web whenever boards were reset or another device played.
static func _merged_score(have_remote: bool, remote: Dictionary, pending: Dictionary, id: StringName, local_total: int) -> int:
	var key := String(id)
	if have_remote:
		return int(remote.get(key, 0)) + int(pending.get(key, 0))
	return local_total

## Contribution of queued (not yet accepted) runs per crew, for runs created in
## the current UTC day (or ISO week when `weekly`).
static func _pending_by_crew(save_manager: SaveManager, weekly: bool) -> Dictionary:
	var out: Dictionary = {}
	if save_manager == null:
		return out
	var period := _week_id() if weekly else _today_id()
	for entry in save_manager.pending_submissions:
		var record: Dictionary = entry.get("record", {})
		var created := int(record.get("client_created_at", 0))
		# Rule C (Oct 10): a queued run only adds to today's numbers if it was
		# played on the current server day; older ones become personal scores.
		if created <= 0 or not RunSubmission.counts_today(record) \
				or _period_of(int(ServerClock.to_server(created)), weekly) != period:
			continue
		var id := String(record.get("community_id", ""))
		if id.is_empty():
			continue
		out[id] = int(out.get(id, 0)) + int(record.get("contribution", 0))
	return out

static func _period_of(unix_seconds: int, weekly: bool) -> String:
	if not weekly:
		return Time.get_datetime_string_from_unix_time(unix_seconds, true).substr(0, 10)
	var date := Time.get_datetime_dict_from_unix_time(unix_seconds)
	return BackendClient._iso_week_for(date.year, date.month, date.day)

static func _remote_scores() -> Dictionary:
	if _remote_rows.is_empty() or _remote_period_id != _today_id():
		return {}
	return _scores_from(_remote_rows)

static func _remote_weekly_scores() -> Dictionary:
	if _weekly_rows.is_empty() or _weekly_period_id != _week_id():
		return {}
	return _scores_from(_weekly_rows)

static func _scores_from(rows: Array) -> Dictionary:
	var scores: Dictionary = {}
	for row in rows:
		if not row is Dictionary:
			continue
		var id := String(row.get("communityId", row.get("id", "")))
		if id.begins_with("community_"):
			id = id.trim_prefix("community_")
		if id.is_empty():
			continue
		scores[id] = maxi(int(scores.get(id, 0)), int(row.get("score", 0)))
	return scores

# ---------------------------------------------------------------------------
# Crew/weekly fetch + cache plumbing
# ---------------------------------------------------------------------------

static func _maybe_refresh_weekly() -> void:
	if _weekly_fetching:
		return
	var backend := BackendClient.instance
	if backend == null or not backend.is_available():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _weekly_fetched_at >= 0.0 and now - _weekly_fetched_at < CREW_CACHE_SECONDS:
		return
	_weekly_fetched_at = now
	_weekly_fetching = true
	backend.fetch_leaderboard_async(&"communities", &"weekly", func(result: Dictionary) -> void:
		_weekly_fetching = false
		if bool(result.get("ok", false)):
			_weekly_rows = result.get("rows", [])
			_weekly_period_id = String(result.get("periodId", ""))
			_version += 1)

static func _cache_get(key: String) -> Variant:
	if not _crew_cache.has(key):
		return null
	var entry: Dictionary = _crew_cache[key]
	if Time.get_ticks_msec() / 1000.0 - float(entry.get("at", 0.0)) > CREW_CACHE_SECONDS:
		_crew_cache.erase(key)
		return null
	return entry.get("value")

static func _cache_set(key: String, value: Variant) -> void:
	_crew_cache[key] = {"at": Time.get_ticks_msec() / 1000.0, "value": value}
	_version += 1

## Marks a key as in-flight so screens do not fire duplicate requests.
static func _cache_pending(key: String) -> bool:
	if not _crew_cache.has(key):
		return false
	var entry: Dictionary = _crew_cache[key]
	if bool(entry.get("pending", false)):
		return float(entry.get("at", 0.0)) + CREW_CACHE_SECONDS > Time.get_ticks_msec() / 1000.0
	return false

static func _maybe_fetch_crew(key: String, community_id: StringName, period: StringName) -> void:
	var backend := BackendClient.instance
	if backend == null or not backend.is_available() or _cache_pending(key):
		return
	if _cache_get(key) != null:
		return
	_crew_cache[key] = {"at": Time.get_ticks_msec() / 1000.0, "pending": true, "value": null}
	backend.fetch_crew_players_async(community_id, period, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			var rows: Array = result.get("rows", [])
			for i in range(rows.size()):
				rows[i]["rank"] = i + 1
				rows[i]["you"] = _is_me(rows[i])
			_cache_set(key, rows)
		else:
			_crew_cache.erase(key))

static func _maybe_fetch_members(key: String, community_id: StringName) -> void:
	var backend := BackendClient.instance
	if backend == null or not backend.is_available() or _cache_pending(key):
		return
	if _cache_get(key) != null:
		return
	_crew_cache[key] = {"at": Time.get_ticks_msec() / 1000.0, "pending": true, "value": null}
	backend.crew_members_count_async(community_id, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			_cache_set(key, int(result.get("count", 0)))
			_snapshot_set(key, int(result.get("count", 0)))
		else:
			_crew_cache.erase(key))

static func _maybe_fetch_champion(key: String, community_id: StringName) -> void:
	var backend := BackendClient.instance
	if backend == null or not backend.is_available() or _cache_pending(key):
		return
	if _crew_cache.has(key) and _cache_get(key) != null:
		return
	_crew_cache[key] = {"at": Time.get_ticks_msec() / 1000.0, "pending": true, "value": null}
	backend.fetch_last_champion_async(community_id, func(result: Dictionary) -> void:
		if bool(result.get("ok", false)):
			_cache_set(key, result.get("champion", {}))
		else:
			_crew_cache.erase(key))

## Offline single-row crew list built from the local save.
static func _local_crew_rows(save_manager: SaveManager, community_id: StringName, period: StringName) -> Array:
	var score := 0
	if save_manager != null:
		score = save_manager.week_total(community_id) if period == &"weekly" else save_manager.day_total(community_id)
	var uid := _my_uid()
	return [{
		"uid": uid,
		"name": "You",
		"score": score,
		"runs": 0,
		"rank": 1 if score > 0 else 0,
		"you": true,
		"local": true,
	}]

static func _my_uid() -> String:
	var backend := BackendClient.instance
	return backend.player_id if backend != null else ""

static func _is_me(row: Dictionary) -> bool:
	var uid := _my_uid()
	return not uid.is_empty() and String(row.get("uid", "")) == uid

static func _week_id() -> String:
	return BackendClient.week_id()

static func _today_id() -> String:
	return BackendClient.day_id()
