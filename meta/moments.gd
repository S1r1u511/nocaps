extends RefCounted
class_name Moments

## Event catalog + priority queue for the competition layer (docs/15 §3).
##
## §3 is data here: every element has an id, emotion (SCOREBOARD/PRIDE), priority
## (the §3 table order), cooldown, copy templates and the surfaces it may appear
## on (`run_toast` / `result_card` / `home_banner` / `board_row`). A detected
## event is enqueued once per key (dedupe), shown one at a time per popup surface,
## and re-shown only after its cooldown (home banners additionally keep a ≥20 s gap
## between non-critical banners).
##
## Detection reads `meta/race.gd` (only when it exists — same adapter pattern as
## `meta/quests.gd`), `meta/standings.gd`, `meta/quests.gd` signals and
## `SaveManager` run facts (new best / streak / tier crossed). This module owns no
## UI: `ui/moment_popup.gd` renders `next_for()` / `peek_rows()`, calls
## `dismiss(id)`, and listens to `moment_ready(surface)`.
##
## See docs/15 §3 for the trigger semantics of each id.

signal moment_ready(surface: StringName)

## Emitted when the persisted dev-panel master switch changes.
signal enabled_changed(enabled: bool)

const SURFACE_RUN := &"run_toast"
const SURFACE_RESULT := &"result_card"
const SURFACE_HOME := &"home_banner"
const SURFACE_BOARD := &"board_row"

## Minimum seconds between two non-critical home banners (docs/15 §3).
const HOME_BANNER_GAP := 20.0

## Master switches, persisted so a dev-panel choice survives a relaunch. The
## master switch gates every surface (no moment UI anywhere while off); home
## banners are additionally off by default because they are the only surface not
## mounted in a reserved slot (audit A 2026-09-27, stability pass).
const SETTINGS_PATH := "user://moments_settings.json"
const DEFAULT_ENABLED := true
const DEFAULT_BANNERS_ENABLED := false

const EMOTION_SCOREBOARD := "SCOREBOARD"
const EMOTION_PRIDE := "PRIDE"

const RACE_SCRIPT_PATH := "res://meta/race.gd"
const SECONDS_PER_DAY := 86400

## The §3 catalog. `priority` is the table order (lower shows first); `cooldown`
## is the minimum seconds before the same id can fire again. `accent` is a visual
## role the popup maps to kit colors (gold / green / red).
const CATALOG: Dictionary = {
	"gap_to_pass": {
		"emotion": EMOTION_SCOREBOARD, "priority": 10, "cooldown": 30.0,
		"accent": "red", "critical": false,
		"surfaces": [SURFACE_RUN, SURFACE_BOARD],
		"title": "{gap} TO PASS {crew}", "detail": "counts down as you score",
	},
	"overtake": {
		"emotion": EMOTION_SCOREBOARD, "priority": 20, "cooldown": 20.0,
		"accent": "gold", "critical": true,
		"surfaces": [SURFACE_RUN, SURFACE_RESULT, SURFACE_BOARD],
		"title": "{crew} TAKES #{rank}!", "detail": "Passed {rival}",
	},
	"crew_rank_up": {
		"emotion": EMOTION_SCOREBOARD, "priority": 30, "cooldown": 20.0,
		"accent": "green", "critical": false,
		"surfaces": [SURFACE_RUN],
		"title": "You're now #{rank} in {crew}", "detail": "Passed {rival}",
	},
	"rank_moved": {
		"emotion": EMOTION_SCOREBOARD, "priority": 40, "cooldown": 0.0,
		"accent": "gold", "critical": true,
		"surfaces": [SURFACE_RESULT],
		"title": "YOUR RUN MOVED {crew}", "detail": "#{from} → #{to} · +{contribution} for {crew}",
	},
	"catch_cta": {
		"emotion": EMOTION_SCOREBOARD, "priority": 50, "cooldown": 0.0,
		"accent": "gold", "critical": false,
		"surfaces": [SURFACE_RESULT],
		"title": "ONE MORE — CATCH {crew}", "detail": "{gap} behind",
	},
	"live_ticker": {
		"emotion": EMOTION_SCOREBOARD, "priority": 60, "cooldown": 20.0,
		"accent": "red", "critical": false,
		"surfaces": [SURFACE_HOME],
		"title": "{rival} +{gain} in the last {min} min", "detail": "closing in!",
	},
	"rank_arrow": {
		"emotion": EMOTION_SCOREBOARD, "priority": 70, "cooldown": 0.0,
		"accent": "green", "critical": false,
		"surfaces": [SURFACE_BOARD],
		"title": "{arrow}{n}", "detail": "{crew}",
	},
	"momentum": {
		"emotion": EMOTION_SCOREBOARD, "priority": 80, "cooldown": 20.0,
		"accent": "red", "critical": false,
		"surfaces": [SURFACE_BOARD],
		"title": "surging · +{gain} in {min} min", "detail": "{crew}",
	},
	"overtake_feed": {
		"emotion": EMOTION_SCOREBOARD, "priority": 90, "cooldown": 20.0,
		"accent": "gold", "critical": false,
		"surfaces": [SURFACE_BOARD],
		"title": "{by} overtook {over}", "detail": "{min} min ago",
	},
	"countdown": {
		"emotion": EMOTION_SCOREBOARD, "priority": 100, "cooldown": 0.0,
		"accent": "red", "critical": true,
		"surfaces": [SURFACE_BOARD, SURFACE_HOME],
		"title": "TODAY ENDS {clock}", "detail": "final hour — all runs count",
	},
	"new_best": {
		"emotion": EMOTION_PRIDE, "priority": 110, "cooldown": 0.0,
		"accent": "gold", "critical": true,
		"surfaces": [SURFACE_RESULT],
		"title": "NEW BEST!", "detail": "{score}",
	},
	"streak": {
		"emotion": EMOTION_PRIDE, "priority": 120, "cooldown": 0.0,
		"accent": "green", "critical": false,
		"surfaces": [SURFACE_RESULT, SURFACE_HOME],
		"title": "{n}-DAY STREAK", "detail": "every landing counts",
	},
	"tier_crossed": {
		"emotion": EMOTION_PRIDE, "priority": 130, "cooldown": 0.0,
		"accent": "gold", "critical": false,
		"surfaces": [SURFACE_RESULT, SURFACE_HOME],
		"title": "{crew} HIT TIER {tier}!", "detail": "crew goal pushed",
	},
	"quest_completed": {
		"emotion": EMOTION_PRIDE, "priority": 140, "cooldown": 0.0,
		"accent": "green", "critical": false,
		"surfaces": [SURFACE_RESULT, SURFACE_HOME],
		"title": "{title}", "detail": "+{reward} crew",
	},
}

static var _singleton: Moments

var _queues: Dictionary = {}
## surface -> moment currently visible on a popup surface.
var _visible: Dictionary = {}
## dedupe key -> true; an event with the key never enqueues twice this session.
var _seen: Dictionary = {}
## id -> last show/dismiss time (for cooldowns).
var _shown_at: Dictionary = {}
## surface -> last show/dismiss time (for the home-banner gap).
var _surface_at: Dictionary = {}
var _race_instance: Object = null
var _bound: bool = false
var _enabled: bool = DEFAULT_ENABLED
var _banners_enabled: bool = DEFAULT_BANNERS_ENABLED


## Shared signal source. Created (and bound to Quests) on first use.
static func instance() -> Moments:
	if _singleton == null:
		_singleton = Moments.new()
		_singleton._bind()
	return _singleton


func _init() -> void:
	_queues = {
		SURFACE_RUN: [],
		SURFACE_RESULT: [],
		SURFACE_HOME: [],
		SURFACE_BOARD: [],
	}
	_load_settings()


func _bind() -> void:
	if _bound:
		return
	_bound = true
	var quests := Quests.instance()
	if not quests.quest_completed.is_connected(_on_quest_completed):
		quests.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(quest: Dictionary) -> void:
	# Pride moment for a finished quest; dedupe per quest id + UTC day.
	var day := int(Time.get_unix_time_from_system() / SECONDS_PER_DAY)
	_enqueue("quest_completed", SURFACE_RESULT, {
		"title": String(quest.get("title", "Quest complete")),
		"reward": int(quest.get("reward", 0)),
		"key": "quest:%s:%d" % [String(quest.get("id", "")), day],
	}, Time.get_unix_time_from_system())


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Highest-priority ready moment for `surface`, or `{}`. Popup surfaces hold at
## most one at a time; `board_row` returns the top row without marking it visible.
static func next_for(surface: StringName, now: float = -1.0) -> Dictionary:
	return instance()._next_for(surface, _now(now))


## All ready row moments for `surface`, ordered by priority (board rows).
static func peek_rows(surface: StringName, now: float = -1.0) -> Array:
	return instance()._peek_rows(surface, _now(now))


## Consumes a moment: removes it, starts its cooldown, and pings the surface.
static func dismiss(id: String, now: float = -1.0) -> void:
	instance()._dismiss(id, _now(now))


## Raises a catalog moment directly (screens/run may have context this module
## cannot see). Returns false when the id/surface is invalid or the key is a dup.
static func push(id: String, surface: StringName, ctx: Dictionary = {}, now: float = -1.0) -> bool:
	return instance()._enqueue(id, surface, ctx, _now(now))


## Clears all queued/seen/cooldown state (tests, account changes).
static func reset() -> void:
	instance()._reset()


## Master switch (dev panel, persisted). While off no moment UI appears on any
## surface: reads return nothing and popups refuse to show.
static func is_enabled() -> bool:
	return instance()._enabled


static func set_enabled(value: bool) -> void:
	var inst := instance()
	if inst._enabled == value:
		return
	inst._enabled = value
	inst._save_settings()
	inst.enabled_changed.emit(value)


## Home banners are off by default (only reserved-slot surfaces stay on).
static func banners_enabled() -> bool:
	return instance()._banners_enabled


static func set_banners_enabled(value: bool) -> void:
	var inst := instance()
	if inst._banners_enabled == value:
		return
	inst._banners_enabled = value
	inst._save_settings()


static func observe_run(save: SaveManager, payload: Dictionary, race: Object = null, rows: Array = [], now: float = -1.0) -> void:
	instance()._observe_run(save, payload, race, rows, _now(now))


static func observe_result(save: SaveManager, payload: Dictionary, race: Object = null, rows: Array = [], now: float = -1.0) -> void:
	instance()._observe_result(save, payload, race, rows, _now(now))


static func observe_home(save: SaveManager, race: Object = null, rows: Array = [], now: float = -1.0) -> void:
	instance()._observe_home(save, race, rows, _now(now))


static func observe_board(save: SaveManager, race: Object = null, rows: Array = [], now: float = -1.0) -> void:
	instance()._observe_board(save, race, rows, _now(now))


# ---------------------------------------------------------------------------
# Queue internals
# ---------------------------------------------------------------------------

func _next_for(surface: StringName, now: float) -> Dictionary:
	if not _enabled:
		return {}
	var queue: Array = _queues.get(surface, [])
	# Popup surfaces: return the already-visible moment, else the top ready one.
	if surface != SURFACE_BOARD:
		var visible: Dictionary = _visible.get(surface, {})
		if not visible.is_empty():
			return visible
	for moment in queue:
		if _is_ready(moment, now):
			if surface != SURFACE_BOARD:
				_visible[surface] = moment
				_surface_at[surface] = now
			return moment
	return {}


func _peek_rows(surface: StringName, now: float) -> Array:
	var out: Array = []
	if not _enabled:
		return out
	for moment in _queues.get(surface, []):
		if _is_ready(moment, now):
			out.append(moment)
	return out


func _dismiss(id: String, now: float) -> void:
	for surface in _queues:
		var queue: Array = _queues[surface]
		for i in range(queue.size()):
			if String(queue[i].get("id", "")) != id:
				continue
			_shown_at[id] = now
			_surface_at[surface] = now
			queue.remove_at(i)
			if String(_visible.get(surface, {}).get("id", "")) == id:
				_visible.erase(surface)
			emit_signal("moment_ready", surface)
			return
	for surface in _visible.keys():
		if String(_visible[surface].get("id", "")) == id:
			_shown_at[id] = now
			_surface_at[surface] = now
			_visible.erase(surface)
			emit_signal("moment_ready", surface)
			return


func _is_ready(moment: Dictionary, now: float) -> bool:
	var id := String(moment.get("id", ""))
	var def: Dictionary = CATALOG.get(id, {})
	var cooldown := float(def.get("cooldown", 0.0))
	if cooldown > 0.0 and now - float(_shown_at.get(id, -INF)) < cooldown:
		return false
	if StringName(moment.get("surface", &"")) == SURFACE_HOME and not bool(moment.get("critical", false)):
		if now - float(_surface_at.get(SURFACE_HOME, -INF)) < HOME_BANNER_GAP:
			return false
	return true


func _enqueue(id: String, surface: StringName, ctx: Dictionary, now: float) -> bool:
	var def: Dictionary = CATALOG.get(id, {})
	if def.is_empty():
		return false
	var surfaces: Array = def.get("surfaces", [])
	if not surfaces.has(surface):
		return false
	var key := String(ctx.get("key", id))
	if _seen.has(key):
		return false
	_seen[key] = true
	var moment := {
		"id": id,
		"key": key,
		"emotion": String(def.get("emotion", EMOTION_SCOREBOARD)),
		"priority": int(def.get("priority", 999)),
		"surface": surface,
		"accent": String(def.get("accent", "gold")),
		"critical": bool(def.get("critical", false)),
		"title": _format(String(def.get("title", "")), ctx),
		"detail": _format(String(def.get("detail", "")), ctx),
		"context": ctx.duplicate(true),
		"created_at": now,
	}
	var queue: Array = _queues[surface]
	queue.append(moment)
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("priority", 999)) == int(b.get("priority", 999)):
			return float(a.get("created_at", 0.0)) < float(b.get("created_at", 0.0))
		return int(a.get("priority", 999)) < int(b.get("priority", 999)))
	emit_signal("moment_ready", surface)
	return true


func _reset() -> void:
	for surface in _queues:
		_queues[surface].clear()
	_visible.clear()
	_seen.clear()
	_shown_at.clear()
	_surface_at.clear()
	# Tests and account changes start from the shipped defaults (the dev-panel
	# choice is restored from disk on the next engine launch).
	_enabled = DEFAULT_ENABLED
	_banners_enabled = DEFAULT_BANNERS_ENABLED


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	_enabled = bool(parsed.get("enabled", DEFAULT_ENABLED))
	_banners_enabled = bool(parsed.get("home_banners", DEFAULT_BANNERS_ENABLED))


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"enabled": _enabled,
		"home_banners": _banners_enabled,
	}, "\t"))


# ---------------------------------------------------------------------------
# Detection: run
# ---------------------------------------------------------------------------

func _observe_run(save: SaveManager, payload: Dictionary, race: Object, rows: Array, now: float) -> void:
	var my_id := _crew_id(save, payload)
	var contribution := int(payload.get("contribution", payload.get("score", 0)))
	var my_score := int(payload.get("score", 0))
	var resolved := _rows(save, rows)
	var client := _race_from(race)
	if client != null and client.has_method("note_run"):
		client.call("note_run", contribution, now)
	if client != null and client.has_method("run_overtake"):
		var passed: Variant = client.call("run_overtake", resolved, my_id, contribution, my_score)
		if passed is Dictionary and not passed.is_empty():
			_enqueue("overtake", SURFACE_RUN, {
				"crew": _name_by_id(resolved, my_id),
				"rival": String(passed.get("name", "")),
				"rank": _rank_if_added(resolved, my_id, contribution),
				"key": "overtake:%s:%s:%d" % [my_id, String(passed.get("id", "")), _day(now)],
			}, now)
	if client != null and client.has_method("gap_to_pass"):
		var gap: Variant = client.call("gap_to_pass", resolved, my_id)
		if gap is Dictionary and not gap.is_empty():
			_enqueue("gap_to_pass", SURFACE_RUN, {
				"crew": String(gap.get("name", "")),
				"gap": int(gap.get("gap", 0)),
				"key": "gap:%s:%s:%d" % [my_id, String(gap.get("id", "")), _day(now)],
			}, now)
	if client != null and client.has_method("crew_rank_up") and payload.has("player_rows"):
		# TODO(gameplay run.gd): the run payload does not yet carry the crew's
		# player ranking, so the crew-rank-up toast stays dormant until it does.
		var up: Variant = client.call("crew_rank_up", payload.get("player_rows", []), _uid(save, payload), contribution)
		if up is Dictionary and not up.is_empty():
			_enqueue("crew_rank_up", SURFACE_RUN, {
				"crew": _name_by_id(resolved, my_id),
				"rank": int(up.get("rank", 0)),
				"rival": String(up.get("name", "")),
				"key": "crew_rank_up:%s:%s:%d" % [my_id, String(up.get("uid", "")), _day(now)],
			}, now)


# ---------------------------------------------------------------------------
# Detection: result
# ---------------------------------------------------------------------------

func _observe_result(save: SaveManager, payload: Dictionary, race: Object, rows: Array, now: float) -> void:
	var my_id := _crew_id(save, payload)
	var contribution := int(payload.get("contribution", payload.get("score", 0)))
	var crew_name := String(payload.get("community_name", _name_by_id(_rows(save, rows), my_id)))
	var resolved := _rows(save, rows)
	var client := _race_from(race)

	var rank_before := int(payload.get("rank_before", -1))
	var rank_after := int(payload.get("rank_after", -1))
	if client != null and client.has_method("rank_moved") and rank_before > 0 and rank_after > 0:
		var moved: Variant = client.call("rank_moved", rank_before, rank_after, crew_name)
		if moved is Dictionary and not moved.is_empty():
			_enqueue("rank_moved", SURFACE_RESULT, {
				"crew": crew_name,
				"from": int(moved.get("from", rank_before)),
				"to": int(moved.get("to", rank_after)),
				"contribution": contribution,
				"key": "rank_moved:%s:%d:%d:%d" % [my_id, rank_before, rank_after, _day(now)],
			}, now)
	if client != null and client.has_method("catch_cta"):
		var cta: Variant = client.call("catch_cta", resolved, my_id, contribution)
		if cta is Dictionary and not cta.is_empty():
			_enqueue("catch_cta", SURFACE_RESULT, {
				"crew": String(cta.get("name", "")),
				"gap": int(cta.get("gap", 0)),
				"key": "catch:%s:%s:%d" % [my_id, String(cta.get("id", "")), _day(now)],
			}, now)

	if bool(payload.get("new_best", false)) and int(payload.get("score", 0)) > 0:
		_enqueue("new_best", SURFACE_RESULT, {
			"score": int(payload.get("score", 0)),
			"key": "new_best:%s:%d" % [_uid(save, payload), int(payload.get("score", 0))],
		}, now)
	var streak := int(payload.get("streak", 0))
	if streak >= 2:
		_enqueue("streak", SURFACE_RESULT, {
			"n": streak,
			"key": "streak:%s:%d" % [_uid(save, payload), _day(now)],
		}, now)
	if bool(payload.get("tier_crossed", false)):
		_enqueue("tier_crossed", SURFACE_RESULT, {
			"crew": crew_name,
			"tier": int(payload.get("tier_after", 0)),
			"key": "tier:%s:%d:%d" % [my_id, int(payload.get("tier_after", 0)), _day(now)],
		}, now)


# ---------------------------------------------------------------------------
# Detection: home / board
# ---------------------------------------------------------------------------

func _observe_home(save: SaveManager, race: Object, rows: Array, now: float) -> void:
	var my_id := _crew_id(save, {})
	var resolved := _rows(save, rows)
	var client := _race_from(race)
	if client != null and client.has_method("live_ticker"):
		var ticker: Variant = client.call("live_ticker", resolved, my_id, now)
		if ticker is Dictionary and not ticker.is_empty():
			var rival_name := _name_by_id(resolved, String(ticker.get("id", "")))
			var gain := int(ticker.get("gain", 0))
			_enqueue("live_ticker", SURFACE_HOME, {
				"rival": rival_name,
				"gain": gain,
				"min": maxi(2, int(float(ticker.get("span_seconds", 0)) / 60.0)),
				"key": "ticker:%s:%s:%d" % [my_id, String(ticker.get("id", "")), _day(now)],
			}, now)
	if client != null and client.has_method("day_ending"):
		var ending: Variant = client.call("day_ending", now)
		if ending is Dictionary and bool(ending.get("last_hour", false)):
			_enqueue("countdown", SURFACE_HOME, {
				"clock": String(ending.get("clock", "")),
				"key": "countdown:%d" % _day(now),
			}, now)


func _observe_board(save: SaveManager, race: Object, rows: Array, now: float) -> void:
	var my_id := _crew_id(save, {})
	var resolved := _rows(save, rows)
	var client := _race_from(race)
	if client == null:
		return
	if client.has_method("gap_to_pass"):
		var gap: Variant = client.call("gap_to_pass", resolved, my_id)
		if gap is Dictionary and not gap.is_empty():
			_enqueue("gap_to_pass", SURFACE_BOARD, {
				"crew": String(gap.get("name", "")),
				"gap": int(gap.get("gap", 0)),
				"key": "gap:%s:%s:%d" % [my_id, String(gap.get("id", "")), _day(now)],
			}, now)
	if client.has_method("momentum_line"):
		var surging: Variant = client.call("momentum_line", now)
		if surging is Array:
			for entry in surging:
				if not entry is Dictionary:
					continue
				_enqueue("momentum", SURFACE_BOARD, {
					"crew": _name_by_id(resolved, String(entry.get("id", ""))),
					"gain": int(entry.get("gain", 0)),
					"min": maxi(2, int(float(entry.get("span_seconds", 0)) / 60.0)),
					"key": "momentum:%s:%d" % [String(entry.get("id", "")), _day(now)],
				}, now)
	if client.has_method("rank_arrows"):
		var arrows: Variant = client.call("rank_arrows", resolved, now)
		if arrows is Dictionary:
			for id in arrows:
				var delta := int(arrows[id])
				if delta == 0:
					continue
				_enqueue("rank_arrow", SURFACE_BOARD, {
					"crew": _name_by_id(resolved, String(id)),
					"arrow": "▲" if delta > 0 else "▼",
					"n": absi(delta),
					"key": "arrow:%s:%s:%d" % [String(id), "up" if delta > 0 else "down", _day(now)],
				}, now)
	if client.has_method("recent_events"):
		var events: Variant = client.call("recent_events", now, my_id)
		if events is Array:
			var shown := 0
			for event in events:
				if shown >= 3 or not event is Dictionary:
					break
				shown += 1
				_enqueue("overtake_feed", SURFACE_BOARD, {
					"by": _name_by_id(resolved, String(event.get("by", ""))),
					"over": _name_by_id(resolved, String(event.get("over", ""))),
					"min": maxi(1, int((now - float(event.get("t", now))) / 60.0)),
					"key": "feed:%s:%s:%d" % [String(event.get("by", "")), String(event.get("over", "")), int(event.get("t", 0.0))],
				}, now)
	if client.has_method("day_ending"):
		var ending: Variant = client.call("day_ending", now)
		if ending is Dictionary and bool(ending.get("last_hour", false)):
			_enqueue("countdown", SURFACE_BOARD, {
				"clock": String(ending.get("clock", "")),
				"key": "countdown:%d" % _day(now),
			}, now)


# ---------------------------------------------------------------------------
# Sources / helpers
# ---------------------------------------------------------------------------

func _race_from(race: Object) -> Object:
	if race != null:
		return race
	if _race_instance != null:
		return _race_instance
	if ResourceLoader.exists(RACE_SCRIPT_PATH):
		var script: Variant = load(RACE_SCRIPT_PATH)
		if script != null and script.can_instantiate():
			_race_instance = script.new()
	return _race_instance


func _rows(save: SaveManager, rows: Array) -> Array:
	if not rows.is_empty():
		return rows
	if save == null:
		return []
	return Standings.communities_today(save)


func _crew_id(save: SaveManager, payload: Dictionary) -> String:
	if save != null and not String(save.selected_community_id).is_empty():
		return String(save.selected_community_id)
	return String(payload.get("community_id", ""))


func _uid(save: SaveManager, payload: Dictionary) -> String:
	var uid := String(payload.get("player_id", ""))
	if uid.is_empty() and save != null:
		uid = save.player_id
	return uid


func _name_by_id(rows: Array, id: String) -> String:
	for row in rows:
		if row is Dictionary and String(row.get("id", "")) == id:
			return String(row.get("name", id))
	return id


func _rank_if_added(rows: Array, my_id: String, contribution: int) -> int:
	var my_score := 0
	for row in rows:
		if row is Dictionary and String(row.get("id", "")) == my_id:
			my_score = int(row.get("score", 0))
			break
	var new_score := my_score + contribution
	var rank := 1
	for row in rows:
		if not row is Dictionary or String(row.get("id", "")) == my_id:
			continue
		if int(row.get("score", 0)) > new_score:
			rank += 1
	return rank


func _format(template: String, ctx: Dictionary) -> String:
	var out := template
	for key in ctx:
		var token := "{%s}" % String(key)
		if out.contains(token):
			out = out.replace(token, str(ctx[key]))
	return out


static func _now(value: float) -> float:
	return value if value >= 0.0 else Time.get_unix_time_from_system()


static func _day(now: float) -> int:
	return int(now / SECONDS_PER_DAY)
