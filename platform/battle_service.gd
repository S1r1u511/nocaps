extends RefCounted
class_name BattleService

## Live crew battles (the same battles the web runs at play.nocaps.fun).
##
## The admin starts a battle on the web: `tournaments/<id>` goes live with
## {title, crews, startAt, durationSec} and two crew boards
## `boards/<id>_<crew>` are reset. Runs that finish inside the battle window add
## their points to their crew's board in the same commit that saves the run
## (`BackendClient._submit`); the rules refuse that write outside the window.
##
## Two ways the game learns about a battle, one decision point:
## - embedded on the platform: the page posts `nocaps-battle` (EmbedService);
## - the app / standalone web game: one query for the live tournament
##   (`refresh()`), at most once a minute and only when a screen asks.
## `board_for()` is the only place that decides which board a run counts for.

## Scores open 5 s after startAt (the web's 3-2-1); the rules use the same window.
const START_DELAY_MS := 5000
## Stay this far inside the window so a run never races the rules' cut-off.
const MARGIN_MS := 1500
## How often the app may look for a live battle.
const REFRESH_MS := 60000
## How often the crew boards may be read while a battle is live and on screen.
const BOARDS_MS := 8000

static var tid: String = ""
static var title: String = ""
static var crews: PackedStringArray = PackedStringArray()
## Local ticks (ms) when scoring opens / closes.
static var start_ms: int = 0
static var end_ms: int = 0
## "embed" or "app" (empty when no battle is known).
static var source: String = ""
## Crew id -> battle points; crew id -> this player's points (from the boards).
static var scores: Dictionary = {}
static var my_scores: Dictionary = {}

static var _last_fetch_ms: int = -REFRESH_MS
static var _last_boards_ms: int = -BOARDS_MS
static var _fetching: bool = false
static var _boards_fetching: bool = false

static func now_ms() -> int:
	return Time.get_ticks_msec()

## Sets the battle window. `starts_in_ms` / `ends_in_ms` are relative to now (ms).
static func set_window(battle_id: String, crew_list: PackedStringArray, starts_in_ms: int, ends_in_ms: int,
		from: String, battle_title: String = "", at_ms: int = -1) -> void:
	var now := now_ms() if at_ms < 0 else at_ms
	if battle_id.is_empty() or not _valid_id(battle_id) or crew_list.is_empty():
		clear()
		return
	if battle_id != tid:
		scores = {}
		my_scores = {}
		_last_boards_ms = -BOARDS_MS
	tid = battle_id
	title = battle_title if not battle_title.is_empty() else _title_from_id(battle_id)
	crews = crew_list
	start_ms = now + starts_in_ms
	end_ms = now + ends_in_ms
	source = from

static func clear() -> void:
	tid = ""
	title = ""
	crews = PackedStringArray()
	start_ms = 0
	end_ms = 0
	source = ""
	scores = {}
	my_scores = {}

## Board doc id a run of `crew` finishing now counts for, or "" when none.
static func board_for(crew: String, at_ms: int = -1) -> String:
	if tid.is_empty() or not crews.has(crew):
		return ""
	var now := now_ms() if at_ms < 0 else at_ms
	if now < start_ms + MARGIN_MS or now > end_ms - MARGIN_MS:
		return ""
	return "%s_%s" % [tid, crew]

static func is_live(at_ms: int = -1) -> bool:
	var now := now_ms() if at_ms < 0 else at_ms
	return not tid.is_empty() and now >= start_ms and now < end_ms

static func in_countdown(at_ms: int = -1) -> bool:
	var now := now_ms() if at_ms < 0 else at_ms
	return not tid.is_empty() and now < start_ms

static func seconds_left(at_ms: int = -1) -> int:
	var now := now_ms() if at_ms < 0 else at_ms
	if tid.is_empty():
		return 0
	return maxi(0, int(ceil(float(end_ms - maxi(now, start_ms)) / 1000.0)))

static func clock_text(at_ms: int = -1) -> String:
	var s := seconds_left(at_ms)
	return "%d:%02d" % [s / 60, s % 60]

## Force a look-up only when the last one is older than `max_age_ms` (Home show /
## app resume): one query, no extra polling. Otherwise the normal 60 s throttle
## stays in charge.
static func refresh_if_stale(max_age_ms: int = 20000) -> void:
	if now_ms() - _last_fetch_ms < max_age_ms:
		return
	refresh(true)

## Looks for a live battle (app / standalone only; the embed path is pushed).
static func refresh(force: bool = false) -> void:
	if EmbedService.is_embedded() or _fetching:
		return
	var backend := BackendClient.instance
	if backend == null or not backend.is_available():
		return
	var now := now_ms()
	if not force and now - _last_fetch_ms < REFRESH_MS:
		return
	_last_fetch_ms = now
	_fetching = true
	backend.fetch_live_battle_async(func(result: Dictionary) -> void:
		_fetching = false
		absorb(result, now_ms()))

## Applies a fetch_live_battle_async result. `result.battle` empty = no battle.
static func absorb(result: Dictionary, at_ms: int) -> void:
	if not bool(result.get("ok", false)):
		return  # offline: keep what we knew
	if source == "embed":
		return
	var battle: Dictionary = result.get("battle", {})
	if battle.is_empty():
		clear()
		return
	var server_ms := int(result.get("server_ms", 0))
	if server_ms <= 0:
		server_ms = int(ServerClock.now() * 1000.0)
	var opens := int(battle.get("start_ms", 0)) + START_DELAY_MS
	var closes := opens + int(battle.get("duration_s", 0)) * 1000
	if closes <= server_ms:
		clear()
		return
	set_window(String(battle.get("id", "")), battle.get("crews", PackedStringArray()),
		opens - server_ms, closes - server_ms, "app", String(battle.get("title", "")), at_ms)

## Reads the crew boards while a battle is live (throttled; call from a visible screen).
static func refresh_boards(force: bool = false) -> void:
	if _boards_fetching or not (is_live() or in_countdown()):
		return
	var backend := BackendClient.instance
	if backend == null or not backend.is_available():
		return
	var now := now_ms()
	if not force and now - _last_boards_ms < BOARDS_MS:
		return
	_last_boards_ms = now
	_boards_fetching = true
	var asked := tid
	backend.fetch_battle_boards_async(tid, crews, func(result: Dictionary) -> void:
		_boards_fetching = false
		if bool(result.get("ok", false)) and asked == tid:
			scores = result.get("scores", {})
			my_scores = result.get("mine", {}))

## Crews in the battle with their points, highest first: [{id, score, mine}].
static func standings() -> Array:
	var rows: Array = []
	for crew in crews:
		rows.append({"id": crew, "score": int(scores.get(crew, 0)), "mine": int(my_scores.get(crew, 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	return rows

static func _valid_id(value: String) -> bool:
	return RegEx.create_from_string("^[a-z0-9_-]{1,80}$").search(value) != null

static func _title_from_id(battle_id: String) -> String:
	var words: PackedStringArray = []
	for part in battle_id.split("-", false):
		if part.is_valid_int():
			words.append("#" + part)
		else:
			words.append(part.capitalize())
	return " ".join(words)
